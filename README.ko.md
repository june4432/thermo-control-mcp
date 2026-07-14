# thermo-control-mcp

[English](README.md) | **한국어**

Claude Code(또는 모든 MCP 클라이언트)가 맥의 온도를 모니터링하고 팬 속도를 제어할 수 있게 해주는 [MCP](https://modelcontextprotocol.io) 서버입니다. LLM이 무엇을 요청하든 안전 한계를 강제하는 root 데몬이 함께 동작합니다.

![demo](assets/demo.gif)

*실화입니다: 배터리 메뉴는 "터미널" 탓만 했지만, Claude가 폭주하는 언어 서버를 찾아내 팬을 올리고, 끝난 뒤 제어권을 돌려줬습니다. ([Remotion](https://remotion.dev)으로 렌더링 — 소스는 [`demo/`](demo/)에.)*

```
나:     "20분짜리 Rust 빌드 돌릴 거야. 시원하게 유지해줘."
Claude: [get_thermal_status] → CPU 58°C, 팬은 시스템 제어 중
        [set_fan_speed percent=80 ttl_seconds=1500] → 열이 오르기 전에 팬 가동
        ... 서멀 스로틀링 없이 빌드 완료 ...
        [set_fan_auto] → macOS 제어로 복귀
```

Apple Silicon(M1–M5, M3/M4의 펌웨어 잠금 포함 — [동작 원리](#동작-원리) 참고)에서 동작합니다. 온도 읽기는 권한이 필요 없고, 팬 제어는 작은 root LaunchDaemon을 사용합니다.

## 왜 만들었나

macOS는 팬을 *사후에* 올립니다 — 팬이 돌기 시작할 때쯤이면 CPU는 이미 스로틀링 중이죠. LLM 에이전트는 무거운 빌드, 테스트, 로컬 추론을 *시작하기 전에* 그 사실을 압니다. 이 서버는 에이전트가 기계를 미리 냉각하고, 지속 부하 동안 높은 팬 속도를 유지하고, 끝나면 제어권을 돌려줄 수 있게 합니다.

## 아키텍처

```
Claude Code ── stdio ──> MCP 서버 (Node, 일반 권한)
                            │
                            ├─ 읽기 (온도/RPM/전력) ─── 데몬 없이도 동작
                            │
                            └─ unix socket /var/run/thermod.sock (root:admin 0660)
                                            │
                                     thermod 데몬 (root, launchd)
                                     ├─ IOKit(AppleSMC)으로 SMC 접근
                                     ├─ M3/M4 Ftst 언락 시퀀스
                                     └─ 안전 정책 (하드코딩):
                                        · TTL 데드맨 스위치
                                        · 102°C 열 페일세이프
                                        · RPM은 하드웨어 범위로 클램핑
                                        · 데몬 종료 시 auto 복귀
```

안전 정책은 LLM이 대화하는 MCP 레이어가 아니라 **root 데몬 안에** 있습니다. LLM은 요청할 수 있을 뿐, 결정은 데몬이 합니다.

| 안전장치 | 동작 |
|---|---|
| 데드맨 스위치 | 모든 수동 설정에는 TTL이 붙습니다(기본 15분, 최대 2시간). TTL이 만료되거나, 데몬이 멈추거나, 재부팅되면 팬은 macOS 제어로 복귀합니다. 제어를 유지하려면 에이전트가 갱신 요청을 해야 합니다. |
| 열 페일세이프 | 수동 제어 중 다이 센서가 **102°C**에 도달하면 데몬이 수동 모드를 즉시 포기하고 시스템에 팬을 돌려줍니다. 소켓으로는 설정 변경이 불가능합니다. |
| RPM 클램핑 | 요청된 속도는 하드웨어가 보고한 `[최소, 최대]` 범위로 클램핑됩니다. LLM은 팬을 멈출 수 없습니다. |
| 잠자기/깨어남 처리 | 잠자기를 거치면 펌웨어가 수동 제어를 해제합니다. 유효한(만료되지 않은) 요청이 남아 있을 때만 데몬이 재확립합니다. |
| 로컬 관리자 전용 | 제어 소켓은 `root:admin` 모드 `0660` — 이 기계의 관리자 계정만 명령할 수 있습니다. |

## 요구 사항

- **팬이 있는** Apple Silicon 맥 (MacBook Air는 팬이 없습니다). Intel 맥도 동작할 수 있으나(레거시 `fpe2` 포맷 구현됨) 테스트되지 않았습니다.
- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`) — Swift 데몬 빌드용
- Node.js 18+

## 설치

구성 요소는 두 가지입니다: **MCP 서버**(npm)와 **thermod 데몬**(이 저장소에서 빌드 — root LaunchDaemon이므로 의도적으로 미리 빌드된 바이너리를 배포하지 않습니다. 실행할 것은 직접 빌드하세요).

```bash
git clone https://github.com/june4432/thermo-control-mcp.git
cd thermo-control-mcp

# 1. MCP 서버 빌드
npm install && npm run build

# 2. root 데몬 빌드 + 설치 (비밀번호를 물어봅니다)
sudo ./scripts/install.sh

# 3. Claude Code에 등록
claude mcp add thermo-control -- node "$(pwd)/dist/index.js"
```

MCP 서버를 npm으로 받고 싶다면 (팬 제어에는 여전히 위의 2단계가 필요합니다):

```bash
npm install -g thermo-control-mcp
claude mcp add thermo-control -- thermo-control-mcp
```

2단계 없이도 `get_thermal_status`는 동작합니다(SMC 읽기는 권한이 필요 없음). 제어 도구는 설명이 담긴 에러를 반환합니다.

제거는 `sudo ./scripts/uninstall.sh` — 팬은 시스템 제어로 복귀합니다.

## MCP 도구

| 도구 | 기능 |
|---|---|
| `get_thermal_status` | 센서별 다이 온도(CPU/GPU/메모리), 팬 RPM/모드/범위, 전력(W), 현재 제어 상태와 남은 TTL. |
| `get_heat_sources` | 기계가 *왜* 뜨거운지 진단: 온도 요약 + CPU 상위 프로세스(누적 CPU 시간 vs 가동 시간 — 폭주 프로세스가 바로 드러남). macOS 배터리 메뉴가 "터미널"로 뭉뚱그리는 것을 실제 프로세스 단위로 분해합니다. |
| `set_fan_speed` | `rpm` 또는 `percent`(각 팬의 최소→최대 범위 기준)로 수동 모드 설정. `fan` 인덱스별 지정 가능, `ttl_seconds`(기본 900) 포함. |
| `boost_fans` | 모든 팬을 `ttl_seconds`(기본 600) 동안 100%로. 사전 냉각 단축키. |
| `set_fan_auto` | 수동 제어를 즉시 해제하고 macOS에 반환. |

데몬을 직접 찔러볼 수도 있습니다:

```bash
echo '{"cmd":"status"}' | nc -U /var/run/thermod.sock | python3 -m json.tool
echo '{"cmd":"set","percent":70,"ttl_seconds":300}' | nc -U /var/run/thermod.sock
echo '{"cmd":"auto"}' | nc -U /var/run/thermod.sock
```

데몬 없이 온도만 읽으려면: `daemon/.build/release/thermod status`.

## 동작 원리

팬 상태는 SMC 키에 있습니다(`FNum`, `F0Ac` 실제 RPM, `F0Tg` 목표, `F0Mn`/`F0Mx` 범위, `F0Md` 모드 — Apple Silicon에서는 모두 리틀엔디언 float). 유저스페이스에서 `AppleSMC` IOKit 서비스를 통해 접근합니다. 읽기는 모든 프로세스에 허용되지만 쓰기는 root가 필요하며, 이는 SMC 펌웨어 자체가 키 단위로 강제합니다.

M3/M4 기기에는 관문이 하나 더 있습니다: `thermalmonitord`가 팬을 "시스템 모드"(mode 3)로 붙잡고 있고, 펌웨어는 수동 모드 쓰기를 `0x82` 에러로 거부합니다. 데몬은 커뮤니티에 문서화된 언락을 사용합니다: 먼저 직접 쓰기를 시도하고(M1/M2/M5와 Intel에서는 이걸로 충분), 거부되면 `Ftst`(force-test) 진단 플래그에 `1`을 써서 thermalmonitord의 회수 로직을 억제한 뒤, 모드 쓰기가 성공할 때까지 재시도합니다(보통 3–6초). 수동 제어를 유지하는 동안 `Ftst`는 계속 1이어야 합니다 — 일회성 CLI가 아니라 상주 데몬인 이유 중 하나입니다. 잠자기/깨어남을 거치면 펌웨어가 `Ftst`를 지우는데, 데몬이 감지해서 재설정합니다.

M5에서는 모드 키 대소문자가 바뀌었고(`F0md`) `Ftst` 키가 사라졌습니다 — 둘 다 런타임에 프로브합니다. T2 이전 Intel 맥에는 모드 키 자체가 없어서 레거시 `FS!` 강제 비트마스크를 대신 사용합니다.

온도 센서는 **동적으로 발견**됩니다: 데몬이 SMC의 전체 키 목록(`#KEY` + 인덱스 읽기)을 열거해서 그럴듯한 온도로 해석되는 모든 `T…` 키를 수집합니다 — 수작업 목록 ~20개 대비 M4 Pro에서 291개. 모델별 테이블 없이 모든 칩 변형(base/Pro/Max/Ultra)과 미래 세대를 커버하고, 큐레이션된 카탈로그는 알려진 키의 친숙한 이름만 제공합니다. 값은 선언된 SMC 타입(`flt`, `sp78`, `fpe2`, `ui8/16/32`)에 따라 디코딩되며, 덕분에 Intel의 부호 있는 7.8 고정소수점 온도도 올바르게 읽힙니다.

크레딧: 언락 메커니즘과 프로토콜 동작 대부분은 [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan)이 (`thermalmonitord`와 `AppleSMC.kext` 디컴파일로) 문서화했으며, [raminsharifi/MacFanControl](https://github.com/raminsharifi/MacFanControl), [VirtualSMC SDK](https://github.com/acidanthera/VirtualSMC), [Asahi Linux SMC 문서](https://asahilinux.org/docs/hw/soc/smc/)를 추가로 참고했습니다. 이 프로젝트는 프로토콜을 Swift로 독립 구현했습니다(MIT 라이선스 레퍼런스만 사용).

## 호환성

| 하드웨어 | 상태 |
|---|---|
| M4 Pro (`Mac16,8`) | **엔드투엔드 검증 완료** — 291개 센서 발견, 수동 팬 제어(2.3k→6.2k RPM), TTL 데드맨 복귀 라이브 확인, 소켓과 MCP 도구 양쪽 모두 |
| M1 / M2 / M3 / M5 | 문서화된 동작대로 구현(M1/M2/M5는 직접 모드 쓰기, M3/M4는 `Ftst` 언락), 센서는 기기별 동적 발견. 미테스트 — 리포트 환영 |
| Intel (T2) | 직접 모드 쓰기 + `fpe2`/`sp78` 디코딩 구현, 미테스트 |
| Intel (T2 이전) | 레거시 `FS!` 강제 비트마스크 폴백 구현, 미테스트 |
| MacBook Air | 팬 없음 — 상태 조회는 동작, 제어는 해당 없음 |

## 주의 사항

- **Macs Fan Control, TG Pro 등과 동시에 실행하지 마세요** — 두 컨트롤러가 같은 SMC 키를 두고 싸웁니다.
- `Ftst` 언락은 Apple의 비공개 메커니즘입니다. macOS 업데이트로 바뀌거나 사라질 수 있으니 메이저 OS 업데이트 후에는 재확인하세요.
- 부하 중에 팬을 낮게 설정하는 것은 페일세이프가 보호하지만, 페일세이프는 최후의 방어선이지 온도 조절기가 아닙니다. 의도된 용도는 팬 속도를 *올리는* 것이지, 뜨거운 기계를 조용하게 만드는 것이 아닙니다.
- macOS 펌웨어는 이 도구와 무관하게 자체 열 보호(스로틀링, 비상 종료)를 유지합니다.

## 면책

이 소프트웨어는 비공개 인터페이스로 시스템 열 관리를 조작합니다. 안전장치가 내장되어 있지만 사용에 따른 책임은 사용자에게 있습니다. 제작자는 하드웨어 손상에 책임지지 않습니다.

## 라이선스

[MIT](LICENSE)
