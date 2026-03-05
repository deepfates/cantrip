import { loadQuickJs } from "@sebastianwessel/quickjs";
import variant from "@jitl/quickjs-ng-wasmfile-release-sync";
import {
  shouldInterruptAfterDeadline,
  type QuickJSContext,
  type QuickJSHandle,
  type QuickJSWASMModule,
} from "quickjs-emscripten-core";
import { Depends } from "../../gate/depends";

const DEFAULT_EXECUTION_TIMEOUT_MS = 2000;
const DEFAULT_MEMORY_LIMIT_BYTES = 64 * 1024 * 1024;
const DEFAULT_MAX_STACK_SIZE_BYTES = 1024 * 1024;

type JavascriptVMOptions = {
  executionTimeoutMs?: number;
  memoryLimitBytes?: number;
  maxStackSizeBytes?: number;
};

let quickJsModulePromise: Promise<QuickJSWASMModule> | null = null;

async function getQuickJsModule(): Promise<QuickJSWASMModule> {
  if (!quickJsModulePromise) {
    quickJsModulePromise = loadQuickJs(variant).then((loaded) => loaded.module);
  }
  return quickJsModulePromise;
}

type EvalResult = { ok: true; output: string } | { ok: false; error: string };

/**
 * Manages the execution of code within a persistent QuickJS sandbox session.
 */
export class JsContext {
  private ctx: QuickJSContext;
  private disposed = false;
  private defaultTimeoutMs: number;
  private currentLogs: string[] | null = null;

  private constructor(
    ctx: QuickJSContext,
    options: Required<JavascriptVMOptions>,
  ) {
    this.ctx = ctx;
    this.defaultTimeoutMs = options.executionTimeoutMs;

    if (options.memoryLimitBytes > 0) {
      this.ctx.runtime.setMemoryLimit(options.memoryLimitBytes);
    }
    if (options.maxStackSizeBytes > 0) {
      this.ctx.runtime.setMaxStackSize(options.maxStackSizeBytes);
    }

    this.installConsole();
  }

  static async create(options: JavascriptVMOptions = {}): Promise<JsContext> {
    const module = await getQuickJsModule();
    const ctx = module.newContext();
    const resolved: Required<JavascriptVMOptions> = {
      executionTimeoutMs:
        options.executionTimeoutMs ?? DEFAULT_EXECUTION_TIMEOUT_MS,
      memoryLimitBytes: options.memoryLimitBytes ?? DEFAULT_MEMORY_LIMIT_BYTES,
      maxStackSizeBytes:
        options.maxStackSizeBytes ?? DEFAULT_MAX_STACK_SIZE_BYTES,
    };
    return new JsContext(ctx, resolved);
  }

  /**
   * Executes a string of code in the sandbox, maintaining state from previous calls.
   */
  async evalCode(
    code: string,
    options: { executionTimeoutMs?: number } = {},
  ): Promise<EvalResult> {
    if (this.disposed) {
      return { ok: false, error: "Sandbox is disposed" };
    }

    const timeoutMs = options.executionTimeoutMs ?? this.defaultTimeoutMs;
    if (timeoutMs > 0) {
      this.ctx.runtime.setInterruptHandler(
        shouldInterruptAfterDeadline(Date.now() + timeoutMs),
      );
    } else {
      this.ctx.runtime.removeInterruptHandler();
    }

    this.currentLogs = [];

    try {
      const result = this.ctx.evalCode(code);
      if ("error" in result && result.error !== undefined) {
        const errorHandle = result.error;
        const errorValue = this.ctx.dump(errorHandle);
        errorHandle.dispose();
        return { ok: false, error: formatErrorMessage(errorValue) };
      }

      if (!("value" in result) || result.value === undefined) {
        return { ok: false, error: "Unknown execution result" };
      }

      const valueHandle = result.value;
      const dumped = this.ctx.dump(valueHandle);
      valueHandle.dispose();

      const output = formatOutput(dumped, this.currentLogs);
      return { ok: true, output };
    } catch (err: any) {
      return { ok: false, error: String(err?.message ?? err) };
    } finally {
      this.currentLogs = null;
    }
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.ctx.dispose();
  }

  private installConsole(): void {
    const ctx = this.ctx;
    const consoleHandle = ctx.newObject();
    const levels = ["log", "error", "warn", "info", "debug"];
    const handles: QuickJSHandle[] = [];

    for (const level of levels) {
      const fn = ctx.newFunction(level, (...args) => {
        if (this.currentLogs) {
          const line = args
            .map((arg) => formatDumpedValue(ctx.dump(arg)))
            .join(" ");
          this.currentLogs.push(line);
        }
        return ctx.undefined;
      });
      handles.push(fn);
      ctx.setProp(consoleHandle, level, fn);
    }

    ctx.setProp(ctx.global, "console", consoleHandle);

    consoleHandle.dispose();
    for (const handle of handles) {
      handle.dispose();
    }
  }
}

function formatOutput(value: unknown, logs: string[] | null): string {
  const logText = logs && logs.length ? logs.join("\n") : "";
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

const MAX_STACK_FRAMES = 5;
const MAX_ERROR_CHARS = 512;

function formatErrorMessage(errorValue: unknown): string {
  if (errorValue && typeof errorValue === "object") {
    const err = errorValue as {
      name?: unknown;
      message?: unknown;
      stack?: unknown;
    };
    if (err.message !== undefined) {
      const name = err.name ? String(err.name) : "Error";
      const msg = String(err.message);
      const header = `${name}: ${msg}`;
      if (err.stack) {
        const frames = String(err.stack)
          .split("\n")
          .filter((l) => l.trimStart().startsWith("at "))
          .slice(0, MAX_STACK_FRAMES);
        if (frames.length) {
          const full = `${header}\n${frames.join("\n")}`;
          return full.length > MAX_ERROR_CHARS
            ? full.slice(0, MAX_ERROR_CHARS) + "..."
            : full;
        }
      }
      return header.length > MAX_ERROR_CHARS
        ? header.slice(0, MAX_ERROR_CHARS) + "..."
        : header;
    }
  }
  const text = formatDumpedValue(errorValue);
  return text === "" ? "Unknown error" : text;
}

// --- Dependency Injection ---
/**
 * Shared dependency for JsContext.
 * Use this as a key in dependency_overrides Map.
 */
export const getJsContext = new Depends<JsContext>(function getJsContext() {
  throw new Error(
    "JsContext not provided. Use dependency_overrides: new Map([[getJsContext, () => ctx]])",
  );
});
