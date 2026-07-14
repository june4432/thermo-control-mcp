/**
 * Client for the thermod unix-domain socket (newline-delimited JSON,
 * one request per connection).
 */
import net from "node:net";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { existsSync } from "node:fs";

const execFileAsync = promisify(execFile);

export const SOCKET_PATH =
  process.env.THERMOD_SOCKET ?? "/var/run/thermod.sock";

const THERMOD_BIN_CANDIDATES = [
  process.env.THERMOD_BIN,
  "/usr/local/libexec/thermod",
  new URL("../daemon/.build/release/thermod", import.meta.url).pathname,
].filter((p): p is string => Boolean(p));

export class DaemonUnavailableError extends Error {
  constructor(cause: string) {
    super(
      `thermod daemon is not reachable at ${SOCKET_PATH} (${cause}). ` +
        `Fan CONTROL requires the root daemon. Install it by running ` +
        `'sudo ./scripts/install.sh' in the thermo-control-mcp checkout, ` +
        `then retry.`
    );
    this.name = "DaemonUnavailableError";
  }
}

/**
 * Send one command to the daemon. The `set` command may block up to ~11 s
 * while the Ftst unlock sequence runs, hence the generous default timeout.
 */
export function daemonRequest(
  command: Record<string, unknown>,
  timeoutMs = 20_000
): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(SOCKET_PATH);
    let buffer = "";
    let settled = false;

    const fail = (error: Error) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      reject(error);
    };

    const timer = setTimeout(
      () => fail(new Error(`daemon did not answer within ${timeoutMs} ms`)),
      timeoutMs
    );

    socket.on("connect", () => {
      socket.write(JSON.stringify(command) + "\n");
    });

    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const newline = buffer.indexOf("\n");
      if (newline === -1) return;
      clearTimeout(timer);
      if (settled) return;
      settled = true;
      socket.destroy();
      try {
        resolve(JSON.parse(buffer.slice(0, newline)));
      } catch {
        reject(new Error(`daemon sent unparseable response: ${buffer.slice(0, 200)}`));
      }
    });

    socket.on("error", (error: NodeJS.ErrnoException) => {
      clearTimeout(timer);
      if (error.code === "ENOENT" || error.code === "ECONNREFUSED") {
        fail(new DaemonUnavailableError(error.code));
      } else {
        fail(error);
      }
    });

    socket.on("close", () => {
      clearTimeout(timer);
      fail(new Error("connection closed before a response arrived"));
    });
  });
}

/**
 * Read-only fallback: SMC reads need no privileges, so when the daemon is
 * not installed we can still answer status queries by invoking the thermod
 * binary directly.
 */
export async function statusViaBinary(): Promise<Record<string, unknown>> {
  const bin = THERMOD_BIN_CANDIDATES.find((candidate) => existsSync(candidate));
  if (!bin) {
    throw new DaemonUnavailableError(
      "daemon not running and no thermod binary found for read-only fallback"
    );
  }
  const { stdout } = await execFileAsync(bin, ["status"], {
    timeout: 15_000,
    maxBuffer: 1024 * 1024,
  });
  const status = JSON.parse(stdout) as Record<string, unknown>;
  status.daemon_running = false;
  status.note =
    "Read via unprivileged fallback — the thermod daemon is not running, " +
    "so fan control commands will fail until 'sudo ./scripts/install.sh' is run.";
  return status;
}
