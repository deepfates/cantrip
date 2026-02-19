import { gate } from "../decorator";
import { z } from "zod";
import { JsAsyncContext } from "./js_async_context";
import { TaskComplete } from "../../../entity/errors";
import { Depends } from "../depends";
import type { BrowserContext } from "./browser_context";

/** JSON.stringify that tolerates circular references. */
export function safeStringify(value: unknown, indent?: number): string {
  try {
    return JSON.stringify(value, null, indent);
  } catch {
    return "[unserializable]";
  }
}

export type RlmProgressEvent =
  | { type: "sub_entity_start"; depth: number; query: string }
  | { type: "sub_entity_end"; depth: number }
  | { type: "batch_start"; depth: number; count: number }
  | {
      type: "batch_item";
      depth: number;
      index: number;
      total: number;
      query: string;
    }
  | { type: "batch_end"; depth: number };

export type RlmProgressCallback = (event: RlmProgressEvent) => void;

/** Default progress callback: logs to stderr in the tree format used by the REPL. */
export function defaultProgress(depth: number): RlmProgressCallback {
  const indent = "  ".repeat(depth);
  return (event) => {
    switch (event.type) {
      case "sub_entity_start": {
        const preview =
          event.query.slice(0, 50) + (event.query.length > 50 ? "..." : "");
        console.error(`${indent}├─ [depth:${event.depth}] "${preview}"`);
        break;
      }
      case "sub_entity_end":
        console.error(`${indent}└─ [depth:${event.depth}] done`);
        break;
      case "batch_start":
        console.error(
          `${indent}├─ [depth:${event.depth}] llm_batch(${event.count} tasks)`,
        );
        break;
      case "batch_item": {
        const preview =
          event.query.slice(0, 30) + (event.query.length > 30 ? "..." : "");
        console.error(
          `${indent}│  ├─ [${event.index + 1}/${event.total}] "${preview}"`,
        );
        break;
      }
      case "batch_end":
        console.error(`${indent}└─ [depth:${event.depth}] batch complete`);
        break;
    }
  };
}

/**
 * Formats sandbox execution results into a compact metadata string.
 * This prevents the Agent's prompt history from being flooded with large data dumps.
 */
export function formatRlmMetadata(output: string): string {
  if (!output || output === "undefined") return "[Result: undefined]";
  const length = output.length;
  const preview = output.slice(0, 150).replace(/\n/g, " ");
  return `[Result: ${length} chars] "${preview}${length > 150 ? "..." : ""}"`;
}

/**
 * Dependency key for injecting the RLM sandbox into the tool execution context.
 */
export const getRlmSandbox = new Depends<JsAsyncContext>(
  function getRlmSandbox() {
    throw new Error("RlmSandbox not provided");
  },
);

/**
 * The core 'js' tool for Recursive Language Models.
 * Executes JavaScript in the sandbox and returns only metadata to the LLM.
 */
export const js_rlm = gate(
  "Execute JavaScript in the persistent sandbox. Results are returned as metadata. You MUST use submit_answer() to return your final result.",
  async ({ code, timeout_ms }: { code: string; timeout_ms?: number }, deps) => {
    const sandbox = deps.sandbox as JsAsyncContext;

    try {
      const result = await sandbox.evalCode(code, {
        executionTimeoutMs: timeout_ms,
      });

      if (!result.ok) {
        // Handle the internal bridge signal for termination
        if (result.error.startsWith("SIGNAL_FINAL:")) {
          throw new TaskComplete(result.error.replace("SIGNAL_FINAL:", ""));
        }

        let error = result.error;
        // Provide clear guidance on sandbox physics (Asyncify limitations)
        if (error.includes("Lifetime not alive")) {
          error +=
            " (Note: All sandbox functions are blocking. Do NOT use async/await, async functions, or Promises.)";
        }
        return `Error: ${error}`;
      }

      return formatRlmMetadata(result.output);
    } catch (e: any) {
      if (e instanceof TaskComplete) throw e;

      let msg = String(e?.message ?? e);
      if (msg.includes("Lifetime not alive")) {
        msg +=
          " (Note: All sandbox functions are blocking. Do NOT use async/await, async functions, or Promises.)";
      }
      return `Error: ${msg}`;
    }
  },
  {
    name: "js",
    zodSchema: z.object({
      code: z.string().describe("JavaScript code to execute."),
      timeout_ms: z.number().int().positive().optional(),
    }),
    dependencies: { sandbox: getRlmSandbox },
  },
);

/**
 * Bridges the JS Sandbox to the Host by registering RLM primitives.
 */
export async function registerRlmFunctions(options: {
  sandbox: JsAsyncContext;
  context: unknown;
  onLlmQuery: (query: string, subContext?: unknown) => Promise<string>;
  /** Current recursion depth (0 = top-level agent) */
  depth?: number;
  /** Progress callback for sub-agent activity. Defaults to console.error logging. */
  onProgress?: RlmProgressCallback;
  browserContext?: BrowserContext;
  /** Skip llm_query registration — the medium already presents the call_entity gate as llm_query. */
  skipLlmQuery?: boolean;
}) {
  const { sandbox, context, onLlmQuery, depth = 0, browserContext, skipLlmQuery = false } = options;
  const progress = options.onProgress ?? defaultProgress(depth);

  // 1. Inject the data context as a global variable.
  sandbox.setGlobal("context", context);

  // 2. submit_answer is now a proper done gate (done_for_medium) — registered by the medium.

  // 3. llm_query: Recursive delegation to a sub-agent.
  // When skipLlmQuery is true, the medium already presents the call_entity gate as llm_query.
  if (!skipLlmQuery) {
    sandbox.registerAsyncFunction("llm_query", async (query, subContext) => {
      let q = query;
      let c = subContext;

      // Robustness: handle case where LLM passes an object { query, context } or { input }
      if (typeof query === "object" && query !== null) {
        q = (query as any).query ?? (query as any).input ?? (query as any).task;
        c = c ?? (query as any).context ?? (query as any).subContext;
      }

      if (typeof q !== "string") {
        throw new Error("llm_query(query, context) requires a string query.");
      }

      const childDepth = depth + 1;
      progress({ type: "sub_entity_start", depth: childDepth, query: q });

      const result = await onLlmQuery(q, c);

      progress({ type: "sub_entity_end", depth: childDepth });
      return result;
    });
  }

  // 4. llm_batch is now a proper gate (call_entity_batch) — registered by the medium.

  // 5. Browser automation via opaque handle pattern (optional).
  if (browserContext) {
    await registerBrowserFunctions(sandbox, browserContext);
  }
}

// ---------------------------------------------------------------------------
// Browser Handle Pattern
// ---------------------------------------------------------------------------

/**
 * A host-side table mapping opaque integer IDs to real Taiko objects
 * (ElementWrapper, RelativeSearchElement, etc.) that can't cross the
 * QuickJS serialization boundary.
 */
export class HandleTable {
  private nextId = 1;
  private table = new Map<number, any>();

  /** Store a real object and return an opaque handle for the sandbox. */
  create(
    realObject: any,
    desc: string,
  ): { __h: number; kind: string; desc: string } {
    const id = this.nextId++;
    this.table.set(id, realObject);
    return { __h: id, kind: "taiko_handle", desc };
  }

  /** Look up a real object by handle ID. Throws if not found. */
  resolve(id: number): any {
    const obj = this.table.get(id);
    if (obj === undefined) {
      throw new Error(
        `Invalid handle #${id} — selector may have expired or been mistyped.`,
      );
    }
    return obj;
  }

  /** Resolve an argument that may be a handle, string, or passthrough value. */
  resolveArg(arg: unknown): any {
    if (arg === null || arg === undefined) return arg;
    if (typeof arg === "string") return arg;
    if (typeof arg === "number") return arg;
    if (typeof arg === "object" && (arg as any).__h !== undefined) {
      return this.resolve((arg as any).__h);
    }
    return arg;
  }

  /** Clear all handles. */
  clear(): void {
    this.table.clear();
    this.nextId = 1;
  }
}

/** Selector function names that return ElementWrapper instances. */
const SELECTOR_FNS = [
  "$",
  "button",
  "link",
  "text",
  "textBox",
  "dropDown",
  "checkBox",
  "radioButton",
  "image",
  "listItem",
  "fileField",
  "timeField",
  "range",
  "color",
  "tableCell",
] as const;

/** Proximity function names that accept a selector and return a RelativeSearchElement. */
const PROXIMITY_FNS = [
  "near",
  "above",
  "below",
  "toLeftOf",
  "toRightOf",
  "within",
] as const;

/** Action function names that accept selectors/handles and return void. */
const ACTION_FNS = [
  "click",
  "doubleClick",
  "rightClick",
  "hover",
  "focus",
  "scrollTo",
  "tap",
] as const;

/** Navigation functions that return primitives. */
const NAV_FNS = ["goto", "reload", "goBack", "goForward"] as const;

/**
 * Registers Taiko functions in the QuickJS sandbox using the transparent wrapper pattern.
 *
 * Host functions (`__impl_*`, `__resolve`) handle the real Taiko objects.
 * Sandbox-side JS wrappers (injected via evalCode) create objects with callable
 * methods (.text(), .exists(), etc.) that close over handle IDs and dispatch
 * to `__resolve`. This gives the LLM a near-native Taiko API surface.
 */
async function registerBrowserFunctions(
  sandbox: JsAsyncContext,
  browserContext: BrowserContext,
): Promise<void> {
  const handles = new HandleTable();
  const allowed = new Set(browserContext.getAllowedFunctions());
  const scope = browserContext.buildTaikoScope(
    browserContext.getAllowedFunctions(),
  );

  // -----------------------------------------------------------------------
  // Host functions (prefixed with __impl_ or __resolve — not called by LLM)
  // -----------------------------------------------------------------------

  // --- __impl_selector_*: create handles for selector results ---
  const registeredSelectors: string[] = [];
  for (const name of SELECTOR_FNS) {
    if (!allowed.has(name)) continue;
    const taikoFn = scope[name];
    if (!taikoFn) continue;

    const implName = `__impl_${name}`;
    sandbox.registerAsyncFunction(implName, async (...args: unknown[]) => {
      const resolvedArgs = args.map((a) => handles.resolveArg(a));
      const element = taikoFn(...resolvedArgs);
      const desc = `${name}(${args.map(describeArg).join(", ")})`;
      return handles.create(element, desc);
    });
    registeredSelectors.push(name);
  }

  // --- __impl_proximity_*: create handles for proximity results ---
  const registeredProximity: string[] = [];
  for (const name of PROXIMITY_FNS) {
    if (!allowed.has(name)) continue;
    const taikoFn = scope[name];
    if (!taikoFn) continue;

    const implName = `__impl_${name}`;
    sandbox.registerAsyncFunction(implName, async (...args: unknown[]) => {
      const resolvedArgs = args.map((a) => handles.resolveArg(a));
      const result = taikoFn(...resolvedArgs);
      const desc = `${name}(${args.map(describeArg).join(", ")})`;
      return handles.create(result, desc);
    });
    registeredProximity.push(name);
  }

  // --- __resolve: generic method dispatch on real objects ---
  sandbox.registerAsyncFunction(
    "__resolve",
    async (handleId: unknown, method: unknown, ...args: unknown[]) => {
      if (typeof handleId !== "number") {
        throw new Error("__resolve: first argument must be a handle ID");
      }
      if (typeof method !== "string") {
        throw new Error("__resolve: second argument must be a method name");
      }

      const realObj = handles.resolve(handleId);

      if (typeof realObj[method] !== "function") {
        throw new Error(
          `__resolve: object does not have method '${method}'. ` +
            `This may be a proximity handle (near, above, etc.) which doesn't support element queries.`,
        );
      }

      return await realObj[method](...args);
    },
  );

  // --- Action functions: resolve handles, call Taiko, return void ---
  for (const name of ACTION_FNS) {
    if (!allowed.has(name)) continue;
    const taikoFn = scope[name];
    if (!taikoFn) continue;

    sandbox.registerAsyncFunction(name, async (...args: unknown[]) => {
      const resolvedArgs = args.map((a) => handles.resolveArg(a));
      await taikoFn(...resolvedArgs);
      return undefined;
    });
  }

  // --- write: special handling (text, into?, options?) ---
  if (allowed.has("write") && scope.write) {
    sandbox.registerAsyncFunction(
      "write",
      async (text: unknown, into?: unknown, opts?: unknown) => {
        const resolvedInto = handles.resolveArg(into);
        await scope.write(text, resolvedInto, opts);
        return undefined;
      },
    );
  }

  // --- clear: accepts handle ---
  if (allowed.has("clear") && scope.clear) {
    sandbox.registerAsyncFunction("clear", async (selector: unknown) => {
      await scope.clear(handles.resolveArg(selector));
      return undefined;
    });
  }

  // --- press: key string, options ---
  if (allowed.has("press") && scope.press) {
    sandbox.registerAsyncFunction(
      "press",
      async (key: unknown, opts?: unknown) => {
        await scope.press(key, opts);
        return undefined;
      },
    );
  }

  // --- Scroll without selector ---
  for (const name of [
    "scrollDown",
    "scrollUp",
    "scrollLeft",
    "scrollRight",
  ] as const) {
    if (!allowed.has(name) || !scope[name]) continue;
    sandbox.registerAsyncFunction(name, async (px?: unknown) => {
      await scope[name](px);
      return undefined;
    });
  }

  // --- Navigation functions: return primitives ---
  for (const name of NAV_FNS) {
    if (!allowed.has(name) || !scope[name]) continue;
    const taikoFn = scope[name];

    sandbox.registerAsyncFunction(name, async (...args: unknown[]) => {
      const result = await taikoFn(...args);
      // goto returns a response object — extract useful fields
      if (name === "goto" && result && typeof result === "object") {
        return { url: result.url, status: result.status };
      }
      return result;
    });
  }

  // --- currentURL, title: return strings ---
  if (allowed.has("currentURL") && scope.currentURL) {
    sandbox.registerAsyncFunction("currentURL", async () => {
      return await scope.currentURL();
    });
  }
  if (allowed.has("title") && scope.title) {
    sandbox.registerAsyncFunction("title", async () => {
      return await scope.title();
    });
  }

  // --- Element query functions (backward compat): accept handle, return primitives ---
  sandbox.registerAsyncFunction("elem_text", async (handle: unknown) => {
    const el = handles.resolveArg(handle);
    if (typeof el === "string") {
      throw new Error(
        "elem_text requires a selector handle, not a string. Use text('...') first.",
      );
    }
    if (el && typeof el.text === "function") {
      return await el.text();
    }
    throw new Error("elem_text: element does not support .text()");
  });

  sandbox.registerAsyncFunction("elem_exists", async (handle: unknown) => {
    const el = handles.resolveArg(handle);
    if (typeof el === "string") {
      throw new Error("elem_exists requires a selector handle, not a string.");
    }
    if (el && typeof el.exists === "function") {
      return await el.exists();
    }
    throw new Error("elem_exists: element does not support .exists()");
  });

  sandbox.registerAsyncFunction("elem_value", async (handle: unknown) => {
    const el = handles.resolveArg(handle);
    if (el && typeof el.value === "function") {
      return await el.value();
    }
    throw new Error("elem_value: element does not support .value()");
  });

  sandbox.registerAsyncFunction("elem_isVisible", async (handle: unknown) => {
    const el = handles.resolveArg(handle);
    if (el && typeof el.isVisible === "function") {
      return await el.isVisible();
    }
    throw new Error("elem_isVisible: element does not support .isVisible()");
  });

  sandbox.registerAsyncFunction(
    "elem_attribute",
    async (handle: unknown, name: unknown) => {
      const el = handles.resolveArg(handle);
      if (el && typeof el.attribute === "function") {
        return await el.attribute(name);
      }
      throw new Error("elem_attribute: element does not support .attribute()");
    },
  );

  // --- evaluate: run JS in the browser page ---
  // Taiko's evaluate() expects a function, but functions can't cross the
  // QuickJS serialization boundary. We accept a string expression from the
  // sandbox and wrap it in a function on the host side.
  //
  // We use eval() inside the function body — V8's eval auto-returns the last
  // expression value, so "var x = 1; x + 2" returns 3 without needing "return".
  // This avoids hand-parsing JS to insert return statements.
  if (allowed.has("evaluate") && scope.evaluate) {
    sandbox.registerAsyncFunction("evaluate", async (expr: unknown) => {
      if (typeof expr !== "string") {
        throw new Error(
          'evaluate() requires a string expression, e.g. evaluate("document.title")',
        );
      }
      const fn = new Function(`return eval(${JSON.stringify(expr)})`);
      const result = await scope.evaluate(fn);
      // Auto-stringify objects so they survive QuickJS serialization
      if (
        result !== null &&
        result !== undefined &&
        typeof result === "object"
      ) {
        return JSON.stringify(result);
      }
      return result;
    });
  }

  // --- waitFor ---
  if (allowed.has("waitFor") && scope.waitFor) {
    sandbox.registerAsyncFunction("waitFor", async (selectorOrMs: unknown) => {
      const resolved = handles.resolveArg(selectorOrMs);
      await scope.waitFor(resolved);
      return undefined;
    });
  }

  // --- screenshot ---
  if (allowed.has("screenshot") && scope.screenshot) {
    sandbox.registerAsyncFunction("screenshot", async (opts?: unknown) => {
      return await scope.screenshot(opts);
    });
  }

  // --- Dialog handlers ---
  if (allowed.has("accept") && scope.accept) {
    sandbox.registerAsyncFunction("accept", async (text?: unknown) => {
      await scope.accept(text);
      return undefined;
    });
  }
  if (allowed.has("dismiss") && scope.dismiss) {
    sandbox.registerAsyncFunction("dismiss", async () => {
      await scope.dismiss();
      return undefined;
    });
  }

  // --- Tab management ---
  for (const name of ["openTab", "closeTab", "switchTo"] as const) {
    if (!allowed.has(name) || !scope[name]) continue;
    const taikoFn = scope[name];
    sandbox.registerAsyncFunction(name, async (...args: unknown[]) => {
      await taikoFn(...args);
      return undefined;
    });
  }

  // --- dragAndDrop: both args need handle resolution ---
  if (allowed.has("dragAndDrop") && scope.dragAndDrop) {
    sandbox.registerAsyncFunction(
      "dragAndDrop",
      async (source: unknown, target: unknown) => {
        await scope.dragAndDrop(
          handles.resolveArg(source),
          handles.resolveArg(target),
        );
        return undefined;
      },
    );
  }

  // --- Cookie functions ---
  for (const name of ["setCookie", "deleteCookies"] as const) {
    if (!allowed.has(name) || !scope[name]) continue;
    const taikoFn = scope[name];
    sandbox.registerAsyncFunction(name, async (...args: unknown[]) => {
      await taikoFn(...args);
      return undefined;
    });
  }
  if (allowed.has("getCookies") && scope.getCookies) {
    sandbox.registerAsyncFunction("getCookies", async (...args: unknown[]) => {
      return await scope.getCookies(...args);
    });
  }

  // --- Emulation functions (passthrough, return void) ---
  for (const name of [
    "emulateDevice",
    "emulateNetwork",
    "emulateTimezone",
    "setViewPort",
    "setLocation",
  ] as const) {
    if (!allowed.has(name) || !scope[name]) continue;
    const taikoFn = scope[name];
    sandbox.registerAsyncFunction(name, async (...args: unknown[]) => {
      await taikoFn(...args);
      return undefined;
    });
  }

  // --- Permissions ---
  for (const name of [
    "overridePermissions",
    "clearPermissionOverrides",
  ] as const) {
    if (!allowed.has(name) || !scope[name]) continue;
    const taikoFn = scope[name];
    sandbox.registerAsyncFunction(name, async (...args: unknown[]) => {
      await taikoFn(...args);
      return undefined;
    });
  }

  // --- Network ---
  if (allowed.has("clearIntercept") && scope.clearIntercept) {
    sandbox.registerAsyncFunction(
      "clearIntercept",
      async (...args: unknown[]) => {
        await scope.clearIntercept(...args);
        return undefined;
      },
    );
  }

  // --- Visual/Debug ---
  if (allowed.has("highlight") && scope.highlight) {
    sandbox.registerAsyncFunction("highlight", async (selector: unknown) => {
      await scope.highlight(handles.resolveArg(selector));
      return undefined;
    });
  }
  if (allowed.has("clearHighlights") && scope.clearHighlights) {
    sandbox.registerAsyncFunction("clearHighlights", async () => {
      await scope.clearHighlights();
      return undefined;
    });
  }

  // --- Config ---
  if (allowed.has("setConfig") && scope.setConfig) {
    sandbox.registerAsyncFunction("setConfig", async (opts: unknown) => {
      await scope.setConfig(opts);
      return undefined;
    });
  }
  if (allowed.has("getConfig") && scope.getConfig) {
    sandbox.registerAsyncFunction("getConfig", async (...args: unknown[]) => {
      return await scope.getConfig(...args);
    });
  }

  // --- File upload ---
  if (allowed.has("attach") && scope.attach) {
    sandbox.registerAsyncFunction(
      "attach",
      async (filePath: unknown, to: unknown) => {
        await scope.attach(filePath, handles.resolveArg(to));
        return undefined;
      },
    );
  }

  // -----------------------------------------------------------------------
  // Sandbox-side JS: transparent wrappers injected via evalCode
  // -----------------------------------------------------------------------

  // wrapHandle: takes a raw {__h, kind, desc} and returns an object with methods
  // that dispatch to __resolve. The __h property is preserved so actions can
  // still resolve it.
  //
  // Selector wrappers call __impl_* (host fn) then wrap the result.
  // Proximity wrappers do the same.
  // into() is identity — just passes through.

  const wrapperCode = `
    function __wrapHandle(raw) {
      if (!raw || typeof raw !== "object" || raw.__h === undefined) return raw;
      var id = raw.__h;
      return {
        __h: raw.__h,
        kind: raw.kind,
        desc: raw.desc,
        text: function() { return __resolve(id, "text"); },
        exists: function() { return __resolve(id, "exists"); },
        value: function() { return __resolve(id, "value"); },
        isVisible: function() { return __resolve(id, "isVisible"); },
        attribute: function(name) { return __resolve(id, "attribute", name); }
      };
    }

    ${registeredSelectors
      .map(
        (name) => `
    function ${name}() {
      var args = [];
      for (var i = 0; i < arguments.length; i++) args.push(arguments[i]);
      var raw = __impl_${name}.apply(null, args);
      return __wrapHandle(raw);
    }`,
      )
      .join("\n")}

    ${registeredProximity
      .map(
        (name) => `
    function ${name}() {
      var args = [];
      for (var i = 0; i < arguments.length; i++) args.push(arguments[i]);
      var raw = __impl_${name}.apply(null, args);
      return __wrapHandle(raw);
    }`,
      )
      .join("\n")}

    function into(x) { return x; }
    function to(x) { return x; }

    function isHandle(v) { return !!(v && typeof v === "object" && v.__h !== undefined); }
  `;

  await sandbox.evalCode(wrapperCode);
}

/** Format an argument for the handle description string. */
export function describeArg(arg: unknown): string {
  if (arg === null || arg === undefined) return String(arg);
  if (typeof arg === "string") return JSON.stringify(arg);
  if (typeof arg === "number" || typeof arg === "boolean") return String(arg);
  if (typeof arg === "object" && (arg as any).__h !== undefined) {
    return (arg as any).desc ?? `handle#${(arg as any).__h}`;
  }
  return JSON.stringify(arg);
}
