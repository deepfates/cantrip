import { gate } from "../decorator";
import { z } from "zod";
import { loadQuickJs, type SandboxOptions } from "@sebastianwessel/quickjs";
import variant from "@jitl/quickjs-ng-wasmfile-release-sync";

// Mimicking the output limits from fs.ts
const DEFAULT_MAX_OUTPUT_CHARS = 9500;

type JsRunOptions = {
  code: string;
  timeout_ms?: number;
  max_output_chars?: number;
};

export type JsRunProfile = "default" | "compute" | "fetch" | "fs" | "fetch_fs";

export type JsRunConfig = {
  profile?: JsRunProfile;
  allow_fetch?: boolean;
  allow_fs?: boolean;
  env?: Record<string, unknown>;
  mount_fs?: Record<string, any>;
  node_modules?: Record<string, any>;
  max_timeout_count?: number;
  max_interval_count?: number;
};

let runSandboxedPromise:
  | Promise<Awaited<ReturnType<typeof loadQuickJs>>["runSandboxed"]>
  | null = null;

async function getRunSandboxed() {
  if (!runSandboxedPromise) {
    runSandboxedPromise = loadQuickJs(variant).then(
      (loaded) => loaded.runSandboxed,
    );
  }
  return runSandboxedPromise;
}

export function createJsRunGate(config: JsRunConfig = {}) {
  const defaults = getProfileDefaults(config.profile);

  return gate(
    "Execute JavaScript in a fresh sandbox (no state). Use `export default` to return a value. Fetch/fs depend on profile/config; any fs is virtual/limited.",
    async ({ code, timeout_ms, max_output_chars }: JsRunOptions) => {
      const maxChars = max_output_chars ?? DEFAULT_MAX_OUTPUT_CHARS;
      const logs: string[] = [];

      const options: SandboxOptions = {
        executionTimeout: timeout_ms,
        allowFetch: config.allow_fetch ?? defaults.allow_fetch,
        allowFs: config.allow_fs ?? defaults.allow_fs,
        env: config.env,
        mountFs: config.mount_fs,
        nodeModules: config.node_modules,
        maxTimeoutCount: config.max_timeout_count,
        maxIntervalCount: config.max_interval_count,
        console: {
          log: (...args) => logs.push(args.map(formatDumpedValue).join(" ")),
          error: (...args) => logs.push(args.map(formatDumpedValue).join(" ")),
          warn: (...args) => logs.push(args.map(formatDumpedValue).join(" ")),
          info: (...args) => logs.push(args.map(formatDumpedValue).join(" ")),
          debug: (...args) => logs.push(args.map(formatDumpedValue).join(" ")),
        },
      };

      try {
        const runSandboxed = await getRunSandboxed();
        const result = await runSandboxed(
          async ({ evalCode }) => evalCode(code),
          options,
        );

        if (!result.ok) {
          const errorText = formatErrorMessage(result.error);
          return truncateOutput(`Error: ${errorText}`, maxChars);
        }

        const output = formatOutput(result.data, logs);
        return truncateOutput(output, maxChars);
      } catch (err: any) {
        return truncateOutput(`Error: ${String(err?.message ?? err)}`, maxChars);
      }
    },
    {
      name: "js_run",
      zodSchema: z.object({
        code: z
          .string()
          .describe("The JavaScript code to execute in the sandbox."),
        timeout_ms: z
          .number()
          .int()
          .positive()
          .describe("Execution timeout in milliseconds.")
          .optional(),
        max_output_chars: z
          .number()
          .int()
          .positive()
          .describe("Maximum number of output characters.")
          .optional(),
      }),
    },
  );
}

export const js_run = createJsRunGate();

function getProfileDefaults(
  profile?: JsRunProfile,
): { allow_fetch: boolean; allow_fs: boolean } {
  switch (profile) {
    case "compute":
      return { allow_fetch: false, allow_fs: false };
    case "fetch":
      return { allow_fetch: true, allow_fs: false };
    case "fs":
      return { allow_fetch: false, allow_fs: true };
    case "fetch_fs":
      return { allow_fetch: true, allow_fs: true };
    case "default":
    default:
      return { allow_fetch: true, allow_fs: true };
  }
}

function formatOutput(value: unknown, logs: string[]): string {
  const logText = logs.length ? logs.join("\n") : "";
  const valueText =
    value === undefined
      ? "undefined"
      : value === null
        ? "null"
        : formatDumpedValue(value);

  if (logText && valueText === "undefined") return logText;
  if (logText) return `${logText}\n${valueText}`;
  return valueText;
}

function formatDumpedValue(value: unknown): string {
  if (typeof value === "string") return value;
  if (value === undefined) return "undefined";
  if (value === null) return "null";
  const json = safeStringify(value);
  return json ?? String(value);
}

function safeStringify(value: unknown): string | null {
  try {
    return JSON.stringify(
      value,
      (_key, val) => {
        if (typeof val === "bigint") return val.toString();
        if (typeof val === "symbol") return val.toString();
        if (typeof val === "function") {
          return `[Function ${val.name || "anonymous"}]`;
        }
        if (val instanceof Error) {
          return { name: val.name, message: val.message, stack: val.stack };
        }
        return val;
      },
      2,
    );
  } catch {
    return null;
  }
}

function formatErrorMessage(errorValue: unknown): string {
  if (errorValue && typeof errorValue === "object") {
    const message = (errorValue as { message?: unknown }).message;
    if (message !== undefined) return String(message);
  }
  const text = formatDumpedValue(errorValue);
  return text === "" ? "Unknown error" : text;
}

function truncateOutput(output: string, maxChars: number): string {
  if (output.length <= maxChars) return output;

  const lastNewline = output.lastIndexOf("\n", maxChars);
  const cutoff = lastNewline > maxChars / 2 ? lastNewline : maxChars;
  return (
    output.substring(0, cutoff) +
    `\n\n... [output truncated at ${maxChars} chars]`
  );
}
