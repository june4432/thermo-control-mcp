# thermo-control-mcp

An [MCP](https://modelcontextprotocol.io) server that lets Claude Code (or any MCP client) monitor your Mac's thermals and control fan speed — with a root daemon that enforces safety limits no matter what the LLM asks for.

```
You: "I'm about to run a 20-minute Rust build. Keep the machine cool."
Claude: [get_thermal_status] → CPU 58°C, fans on system control
        [set_fan_speed percent=80 ttl_seconds=1500] → fans spin up before the heat arrives
        ... build runs without thermal throttling ...
        [set_fan_auto] → back to macOS control
```

Works on Apple Silicon (M1–M5, including the M3/M4 firmware lock — see [How it works](#how-it-works)). Reading thermals requires no privileges; fan control uses a small root LaunchDaemon.

## Why

macOS ramps fans *reactively* — by the time they spin up, the CPU has already been throttling. An LLM agent knows *in advance* when it's about to start a heavy build, test suite, or local inference job. This server lets it pre-cool the machine, hold higher fan speeds through sustained load, and hand control back when done.

## Architecture

```
Claude Code ── stdio ──> MCP server (Node, unprivileged)
                            │
                            ├─ reads (temps/RPM/power) ─── works even without the daemon
                            │
                            └─ unix socket /var/run/thermod.sock (root:admin 0660)
                                            │
                                     thermod daemon (root, launchd)
                                     ├─ SMC access via IOKit (AppleSMC)
                                     ├─ M3/M4 Ftst unlock sequence
                                     └─ SAFETY POLICY (hardcoded):
                                        · TTL dead-man switch
                                        · 102°C thermal failsafe
                                        · RPM clamped to hardware range
                                        · revert-to-auto on daemon exit
```

The safety policy lives in the root daemon, **not** in the MCP layer the LLM talks to. The LLM can ask; the daemon decides.

| Safeguard | Behavior |
|---|---|
| Dead-man switch | Every manual setting carries a TTL (default 15 min, max 2 h). When it expires — or the daemon stops, or the machine reboots — fans revert to macOS control. Agents must re-request to keep control. |
| Thermal failsafe | If any die sensor reaches **102°C** while under manual control, the daemon abandons manual mode and returns fans to the system immediately. Not configurable over the socket. |
| RPM clamping | Requested speeds are clamped to the fan's hardware-reported `[min, max]` range. An LLM cannot stop the fans. |
| Sleep/wake handling | Firmware drops manual control across sleep; the daemon re-asserts it only if a valid, unexpired request is still active. |
| Local-admin only | The control socket is `root:admin` mode `0660` — only administrator users on the machine can command it. |

## Requirements

- Apple Silicon Mac **with fans** (MacBook Air has none). Intel Macs may work (the legacy `fpe2` format is implemented) but are untested.
- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`) — for building the Swift daemon
- Node.js 18+

## Install

```bash
git clone https://github.com/june4432/thermo-control-mcp.git
cd thermo-control-mcp

# 1. Build + register the MCP server
npm install && npm run build

# 2. Build + install the root daemon (asks for your password)
sudo ./scripts/install.sh

# 3. Register with Claude Code
claude mcp add thermo-control -- node "$(pwd)/dist/index.js"
```

Without step 2, `get_thermal_status` still works (SMC reads are unprivileged); the control tools return an explanatory error.

Uninstall with `sudo ./scripts/uninstall.sh` — fans revert to system control.

## MCP tools

| Tool | What it does |
|---|---|
| `get_thermal_status` | Per-sensor die temperatures (CPU/GPU/memory), fan RPM/mode/range, power draw (W), current control state and remaining TTL. |
| `get_heat_sources` | Diagnose *why* the machine is hot: temperature summary plus the top CPU-consuming processes (with cumulative CPU time vs uptime, so runaways stand out). Breaks down what macOS's battery menu lumps together as "Terminal". |
| `set_fan_speed` | Manual mode at `rpm` or `percent` (of each fan's min→max range), optionally per-`fan`, with `ttl_seconds` (default 900). |
| `boost_fans` | All fans to 100% for `ttl_seconds` (default 600). Pre-cooling shortcut. |
| `set_fan_auto` | Release manual control back to macOS immediately. |

You can also poke the daemon directly:

```bash
echo '{"cmd":"status"}' | nc -U /var/run/thermod.sock | python3 -m json.tool
echo '{"cmd":"set","percent":70,"ttl_seconds":300}' | nc -U /var/run/thermod.sock
echo '{"cmd":"auto"}' | nc -U /var/run/thermod.sock
```

And read thermals with no daemon at all: `daemon/.build/release/thermod status`.

## How it works

Fan state lives in SMC keys (`FNum`, `F0Ac` actual RPM, `F0Tg` target, `F0Mn`/`F0Mx` range, `F0Md` mode, all floats little-endian on Apple Silicon), accessed from userspace through the `AppleSMC` IOKit service. Reads are allowed for any process; writes require root — enforced per-key by the SMC firmware itself.

On M3/M4 machines there is an extra gate: `thermalmonitord` holds the fans in "system mode" (mode 3) and the firmware rejects manual-mode writes with error `0x82`. The daemon uses the community-documented unlock: try the direct write first (sufficient on M1/M2/M5 and Intel); on rejection, write the `Ftst` (force-test) diagnostic flag to `1`, which suppresses thermalmonitord's reclaim logic, then retry the mode write until it lands (typically 3–6 s). `Ftst` must stay set while manual control is held — one of the reasons this is a persistent daemon rather than a one-shot CLI. The firmware clears `Ftst` across sleep/wake; the daemon detects and re-asserts.

Mode-key casing changed on M5 (`F0md`), and `Ftst` no longer exists there — both are probed at runtime. Pre-T2 Intel Macs have no mode key at all; there the legacy `FS!` force-bitmask is used instead.

Temperature sensors are **discovered dynamically**: the daemon enumerates the SMC's full key list (`#KEY` + read-by-index) and keeps every `T…` key that decodes as a plausible temperature — 291 sensors on an M4 Pro versus ~20 in a hand-curated list. This covers every chip variant (base/Pro/Max/Ultra) and future generations without per-model tables; curated catalogs only contribute friendly names where known. Values decode by declared SMC type (`flt`, `sp78`, `fpe2`, `ui8/16/32`), which also makes Intel's signed 7.8 fixed-point temperatures read correctly.

Credit where due: the unlock mechanism and much of the protocol behavior were documented by [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) (via decompilation of `thermalmonitord` and `AppleSMC.kext`), with additional reference from [raminsharifi/MacFanControl](https://github.com/raminsharifi/MacFanControl), the [VirtualSMC SDK](https://github.com/acidanthera/VirtualSMC), and the [Asahi Linux SMC docs](https://asahilinux.org/docs/hw/soc/smc/). This project implements the protocol independently in Swift (MIT-licensed references only).

## Compatibility

| Hardware | Status |
|---|---|
| M4 Pro (`Mac16,8`) | **Verified end-to-end** — 291 sensors discovered, manual fan control (2.3k→6.2k RPM), TTL dead-man revert observed live, via both the socket and MCP tools |
| M1 / M2 / M3 / M5 | Implemented per documented behavior (direct mode write on M1/M2/M5, `Ftst` unlock on M3/M4); sensors discovered dynamically per machine. Untested — reports welcome |
| Intel (T2) | Direct mode write + `fpe2`/`sp78` decoding implemented, untested |
| Intel (pre-T2) | Legacy `FS!` force-bitmask fallback implemented, untested |
| MacBook Air | No fans — status works, control does not apply |

## Caveats

- **Don't run this alongside Macs Fan Control, TG Pro, or similar** — two controllers will fight over the same SMC keys.
- The `Ftst` unlock is an undocumented Apple mechanism. A macOS update could change or remove it. Re-verify after major OS updates.
- Setting fans low under load is protected by the failsafe, but the failsafe is a backstop, not a thermostat. The intended use is raising fan speed, not silencing a hot machine.
- macOS firmware retains its own independent thermal protection (throttling, emergency shutdown) regardless of this tool.

## Disclaimer

This software manipulates system thermal management using undocumented interfaces. It ships with safety mechanisms, but you use it at your own risk. The authors are not responsible for hardware damage.

## License

[MIT](LICENSE)
