#!/usr/bin/env node
/**
 * thermo-control-mcp — MCP server exposing Mac thermal status and fan control.
 *
 * All writes go through the thermod root daemon, which owns the safety
 * policy (TTL dead-man switch, thermal failsafe, RPM clamping). This layer
 * is deliberately thin: it can ask, but the daemon decides.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  daemonRequest,
  statusViaBinary,
  DaemonUnavailableError,
} from "./daemon-client.js";

const server = new McpServer({
  name: "thermo-control",
  version: "0.1.0",
});

type ToolResult = {
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
};

function ok(payload: unknown): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify(payload, null, 2) }] };
}

function err(error: unknown): ToolResult {
  const message = error instanceof Error ? error.message : String(error);
  return { content: [{ type: "text", text: `Error: ${message}` }], isError: true };
}

server.registerTool(
  "get_thermal_status",
  {
    title: "Get thermal status",
    description:
      "Read the Mac's current thermal state: per-sensor die temperatures " +
      "(CPU/GPU/memory), fan RPM (actual/target/min/max) and mode, power " +
      "draw in watts, and the fan-control state (manual targets, remaining " +
      "TTL, last automatic revert). Use this before and after changing fan " +
      "speeds, or to decide whether pre-cooling is worthwhile.",
    inputSchema: {},
  },
  async () => {
    try {
      return ok(await daemonRequest({ cmd: "status" }));
    } catch (error) {
      if (error instanceof DaemonUnavailableError) {
        try {
          return ok(await statusViaBinary());
        } catch (fallbackError) {
          return err(fallbackError);
        }
      }
      return err(error);
    }
  }
);

server.registerTool(
  "set_fan_speed",
  {
    title: "Set fan speed",
    description:
      "Put the Mac's fans into manual mode at a given speed. Provide either " +
      "'rpm' (absolute) or 'percent' (0-100, mapped onto each fan's min-max " +
      "range). Values are clamped to the hardware's reported safe range. " +
      "The setting expires after ttl_seconds (default 900, max 7200) and " +
      "fans return to system control — call again to renew. A root-owned " +
      "failsafe overrides manual control if any die sensor reaches 102°C. " +
      "Typical use: raise fans BEFORE starting a heavy build/inference job " +
      "so the machine stays out of thermal throttling.",
    inputSchema: {
      rpm: z
        .number()
        .optional()
        .describe("Absolute target RPM (mutually exclusive with percent)"),
      percent: z
        .number()
        .min(0)
        .max(100)
        .optional()
        .describe("Speed as % of each fan's min→max range"),
      fan: z
        .number()
        .int()
        .optional()
        .describe("Fan index to control; omit to apply to all fans"),
      ttl_seconds: z
        .number()
        .int()
        .min(10)
        .max(7200)
        .optional()
        .describe("Seconds until automatic revert to system control (default 900)"),
    },
  },
  async ({ rpm, percent, fan, ttl_seconds }) => {
    if ((rpm === undefined) === (percent === undefined)) {
      return err("provide exactly one of 'rpm' or 'percent'");
    }
    try {
      return ok(
        await daemonRequest({ cmd: "set", rpm, percent, fan, ttl_seconds })
      );
    } catch (error) {
      return err(error);
    }
  }
);

server.registerTool(
  "boost_fans",
  {
    title: "Boost fans to maximum",
    description:
      "Convenience wrapper: run all fans at 100% for a limited time " +
      "(default 600 s). Good for pre-cooling right before a compile, " +
      "video export, or LLM inference burst. Reverts automatically.",
    inputSchema: {
      ttl_seconds: z
        .number()
        .int()
        .min(10)
        .max(7200)
        .optional()
        .describe("Seconds until automatic revert (default 600)"),
    },
  },
  async ({ ttl_seconds }) => {
    try {
      return ok(
        await daemonRequest({
          cmd: "set",
          percent: 100,
          ttl_seconds: ttl_seconds ?? 600,
        })
      );
    } catch (error) {
      return err(error);
    }
  }
);

server.registerTool(
  "set_fan_auto",
  {
    title: "Return fans to system control",
    description:
      "Release manual fan control immediately and hand thermal management " +
      "back to macOS (thermalmonitord). Use when the heavy workload is done.",
    inputSchema: {},
  },
  async () => {
    try {
      return ok(await daemonRequest({ cmd: "auto" }));
    } catch (error) {
      return err(error);
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("fatal:", error);
  process.exit(1);
});
