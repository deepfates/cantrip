import {
  newQuickJSAsyncWASMModuleFromVariant,
  shouldInterruptAfterDeadline,
  type QuickJSAsyncContext,
  type QuickJSAsyncWASMModule,
  type QuickJSHandle,
} from "quickjs-emscripten-core";
import variant from "@jitl/quickjs-ng-wasmfile-release-asyncify";
import { Depends } from "../../gate/depends";

const DEFAULT_EXECUTION_TIMEOUT_MS = 30_000; // longer default for LLM calls
const DEFAULT_MEMORY_LIMIT_BYTES = 256 * 1024 * 1024; // 256MB for large contexts
const DEFAULT_MAX_STACK_SIZE_BYTES = 1024 * 1024;

type JavascriptVMOptions = {
  executionTimeoutMs?: number;
  memoryLimitBytes?: number;
  maxStackSizeBytes?: number;
  module?: QuickJSAsyncWASMModule;
};

let asyncModulePromise: Promise<QuickJSAsyncWASMModule> | null = null;

/**
 * Creates a fresh QuickJS Async WASM module.
 * Use this for recursion safety (Asyncify allows one suspension per module).
 */
export async function createAsyncModule(): Promise<QuickJSAsyncWASMModule> {
  return await newQuickJSAsyncWASMModuleFromVariant(variant);
}

/**
 * Returns a shared QuickJS Async WASM module.
 */
export async function getSharedAsyncModule(): Promise<QuickJSAsyncWASMModule> {
  if (!asyncModulePromise) {
    asyncModulePromise = createAsyncModule();
  }
  return asyncModulePromise;
}

type EvalResult = { ok: true; output: string } | { ok: false; error: string };

/**
 * Async function that can be called from within the sandbox.
 * The sandbox code calls it synchronously, but the WASM suspends
 * while the host-side Promise resolves.
 */
export type AsyncHostFunction = (...args: unknown[]) => Promise<unknown>;

/**
 * Manages the execution of code within a persistent QuickJS sandbox session
 * with support for async host functions via ASYNCIFY.
 *
 * Use this when you need sandbox code to call async functions on the host
 * (e.g., making LLM API calls from within the sandbox).
 */
export class JsAsyncContext {
  private ctx: QuickJSAsyncContext;
  private disposed = false;
  private defaultTimeoutMs: number;
  private currentLogs: string[] | null = null;
  private registeredHandles: QuickJSHandle[] = [];

  private constructor(
    ctx: QuickJSAsyncContext,
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

  static async create(
    options: JavascriptVMOptions = {},
  ): Promise<JsAsyncContext> {
    const module = options.module ?? (await getSharedAsyncModule());
    const ctx = module.newContext();
    const resolved: Required<JavascriptVMOptions> = {
      executionTimeoutMs:
        options.executionTimeoutMs ?? DEFAULT_EXECUTION_TIMEOUT_MS,
      memoryLimitBytes: options.memoryLimitBytes ?? DEFAULT_MEMORY_LIMIT_BYTES,
      maxStackSizeBytes:
        options.maxStackSizeBytes ?? DEFAULT_MAX_STACK_SIZE_BYTES,
      module,
    };
    return new JsAsyncContext(ctx, resolved);
  }

  /**
   * Register an async host function that can be called from sandbox code.
   *
   * The function appears synchronous to sandbox code, but the WASM module
   * suspends while the host Promise resolves.
   *
   * @example
   * ```ts
   * ctx.registerAsyncFunction("call_entity", async (intent, context) => {
   *   const result = await entity.cast(intent, context);
   *   return result;
   * });
   *
   * // In sandbox: var answer = call_entity("summarize", chunk);
   * ```
   */
  registerAsyncFunction(name: string, fn: AsyncHostFunction): void {
    if (this.disposed) {
      throw new Error("Context is disposed");
    }

    const ctx = this.ctx;
    const handle = ctx.newAsyncifiedFunction(name, async (...argHandles) => {
      // Convert handles to native values
      const args = argHandles.map((h) => ctx.dump(h));

      try {
        const result = await fn(...args);
        return this.valueToHandle(result);
      } catch (err: any) {
        throw ctx.newError(String(err?.message ?? err));
      }
    });

    ctx.setProp(ctx.global, name, handle);
    this.registeredHandles.push(handle);
  }

  /**
   * Set a global variable in the sandbox.
   */
  setGlobal(name: string, value: unknown): void {
    if (this.disposed) {
      throw new Error("Context is disposed");
    }

    const handle = this.valueToHandle(value);
    this.ctx.setProp(this.ctx.global, name, handle);
    handle.dispose();
  }

  /**
   * Get the value of a global variable from the sandbox.
   */
  getGlobal(name: string): unknown {
    if (this.disposed) {
      throw new Error("Context is disposed");
    }

    const handle = this.ctx.getProp(this.ctx.global, name);
    const value = this.ctx.dump(handle);
    handle.dispose();
    return value;
  }

  /**
   * Executes a string of code in the sandbox, maintaining state from previous calls.
   * Supports calling async host functions registered via registerAsyncFunction.
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
      // Use evalCodeAsync for asyncified context
      const result = await this.ctx.evalCodeAsync(code);

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

    for (const handle of this.registeredHandles) {
      handle.dispose();
    }
    this.registeredHandles = [];

    this.ctx.dispose();
  }

  private valueToHandle(value: unknown): QuickJSHandle {
    const ctx = this.ctx;

    if (value === null) return ctx.null;
    if (value === undefined) return ctx.undefined;

    switch (typeof value) {
      case "string":
        return ctx.newString(value);
      case "number":
        return ctx.newNumber(value);
      case "boolean":
        return value ? ctx.true : ctx.false;
      case "bigint":
        return ctx.newBigInt(value);
      case "object":
        if (Array.isArray(value)) {
          const arr = ctx.newArray();
          for (let i = 0; i < value.length; i++) {
            const elemHandle = this.valueToHandle(value[i]);
            ctx.setProp(arr, i, elemHandle);
            elemHandle.dispose();
          }
          return arr;
        } else {
          const obj = ctx.newObject();
          for (const [k, v] of Object.entries(value)) {
            const valHandle = this.valueToHandle(v);
            ctx.setProp(obj, k, valHandle);
            valHandle.dispose();
          }
          return obj;
        }
      default:
        return ctx.newString(String(value));
    }
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

function formatErrorMessage(errorValue: unknown): string {
  if (errorValue && typeof errorValue === "object") {
    const message = (errorValue as { message?: unknown }).message;
    if (message !== undefined) return String(message);
  }
  const text = formatDumpedValue(errorValue);
  return text === "" ? "Unknown error" : text;
}

// --- Dependency Injection ---
/**
 * Shared dependency for JsAsyncContext.
 * Use this as a key in dependency_overrides Map.
 */
export const getJsAsyncContext = new Depends<JsAsyncContext>(
  function getJsAsyncContext() {
    throw new Error(
      "JsAsyncContext not provided. Use dependency_overrides: new Map([[getJsAsyncContext, () => ctx]])",
    );
  },
);
