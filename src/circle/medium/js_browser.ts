import { JsAsyncContext } from "./js/async_context";
import type { BrowserContext } from "./browser/context";
import type { Medium } from "../medium";
import { js, getJsMediumSandbox } from "./js";
import type { JsMediumOptions } from "./js";

export type JsBrowserMediumOptions = JsMediumOptions & {
  /** Browser context — provides Taiko functions for browser automation. */
  browserContext: BrowserContext;
};

/**
 * Creates a JS+Browser medium — a QuickJS sandbox with browser automation capabilities.
 *
 * Like `js()`, gates are projected into the sandbox as host functions.
 * Additionally, Taiko browser functions (click, goto, text, etc.) are registered
 * during init, and the HandleTable is owned by the medium.
 *
 * The crystal sees the same single `js` tool with tool_choice: "required".
 */
export function jsBrowser(opts: JsBrowserMediumOptions): Medium {
  const { browserContext, ...jsOpts } = opts;
  const inner = js(jsOpts);

  const medium: Medium = {
    async init(gates, dependency_overrides) {
      // Initialize the JS sandbox first (creates sandbox, projects gates)
      await inner.init(gates, dependency_overrides);

      // Then register browser functions into the now-existing sandbox
      const sandbox = getJsMediumSandbox(inner);
      if (!sandbox) {
        throw new Error("jsBrowser: JS medium init did not create a sandbox");
      }
      await registerBrowserFunctions(sandbox, browserContext);
    },

    crystalView() {
      return inner.crystalView();
    },

    async execute(utterance, options) {
      return inner.execute(utterance, options);
    },

    async dispose() {
      return inner.dispose();
    },

    capabilityDocs(): string {
      const jsDocs = inner.capabilityDocs?.() ?? "";
      const allowedFns = new Set(browserContext.getAllowedFunctions());
      const browserDocs = buildBrowserDocs(allowedFns);

      const sections = [jsDocs];
      if (browserDocs) {
        sections.push(
          "### BROWSER AUTOMATION\nTaiko browser functions are available directly in the sandbox. All functions are blocking (no await needed).\n\n" +
            browserDocs,
        );
      }

      return sections.filter(Boolean).join("\n\n");
    },
  };

  // Expose sandbox from inner medium for advanced use cases
  Object.defineProperty(medium, "sandbox", {
    get() {
      return (inner as any).sandbox;
    },
    enumerable: false,
  });

  return medium;
}

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
export async function registerBrowserFunctions(
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

/**
 * Build browser automation docs filtered by what's actually registered.
 * If allowedFns is undefined, documents everything (full profile).
 */
export function buildBrowserDocs(allowedFns?: Set<string>): string {
  const has = (name: string) => !allowedFns || allowedFns.has(name);

  const sections: string[] = [];

  // Selectors
  const selectorFns = [
    "button", "link", "text", "textBox", "dropDown",
    "checkBox", "radioButton", "image", "$", "listItem", "fileField",
  ];
  const availableSelectors = selectorFns.filter(has);
  if (availableSelectors.length > 0) {
    sections.push(`**Selectors** — return element handles with methods:
- \`${availableSelectors.map((s) => s + "(text)").join("\\`, \\`")}\`
- Methods: \`.text()\` → string, \`.exists()\` → boolean, \`.value()\` → string, \`.isVisible()\` → boolean, \`.attribute(name)\` → string`);
  }

  // Proximity
  const proximityFns = ["near", "above", "below", "toLeftOf", "toRightOf", "within"];
  const availableProximity = proximityFns.filter(has);
  if (availableProximity.length > 0) {
    sections.push(`**Proximity** — refine selectors (accept handles or strings, return handles):
- \`${availableProximity.map((s) => s + "(selector)").join("\\`, \\`")}\``);
  }

  // Actions
  const actionLines: string[] = [];
  const clickFns = ["click", "doubleClick", "rightClick"].filter(has);
  if (clickFns.length > 0)
    actionLines.push(`- \`${clickFns.map((s) => s + "(selector)").join("\\`, \\`")}\``);
  const writeFns = ["write", "clear", "press"].filter(has);
  if (writeFns.length > 0)
    actionLines.push(
      `- \`${writeFns.map((s) => (s === "write" ? "write(text, into(selector)?)" : s === "press" ? "press(key)" : s + "(selector)")).join("\\`, \\`")}\``,
    );
  const interactFns = ["hover", "focus", "scrollTo", "tap"].filter(has);
  if (interactFns.length > 0)
    actionLines.push(`- \`${interactFns.map((s) => s + "(selector)").join("\\`, \\`")}\``);
  const scrollFns = ["scrollDown", "scrollUp"].filter(has);
  const dragFns = ["dragAndDrop"].filter(has);
  if (scrollFns.length > 0 || dragFns.length > 0) {
    const parts = [
      ...scrollFns.map((s) => s + "(pixels?)"),
      ...dragFns.map(() => "dragAndDrop(source, target)"),
    ];
    actionLines.push(`- \`${parts.join("\\`, \\`")}\``);
  }
  if (actionLines.length > 0) {
    sections.push(
      `**Actions** — interact with elements (accept handles or strings):\n${actionLines.join("\n")}`,
    );
  }

  // Navigation
  const navFns = ["goto", "reload", "goBack", "goForward"].filter(has);
  const infoFns = ["currentURL", "title"].filter(has);
  if (navFns.length > 0 || infoFns.length > 0) {
    const navParts = navFns.map((s) => s === "goto" ? "goto(url) → {url, status}" : s + "()");
    const infoParts = infoFns.map((s) => s + "() → string");
    sections.push(`**Navigation** — return primitives:
- \`${[...navParts, ...infoParts].join("\\`, \\`")}\``);
  }

  // Tabs
  const tabFns = ["openTab", "closeTab", "switchTo"].filter(has);
  if (tabFns.length > 0) {
    sections.push(
      `**Tabs**: \`${tabFns.map((s) => (s === "openTab" ? "openTab(url)" : s === "closeTab" ? "closeTab(url?)" : "switchTo(urlOrTitle)")).join("\\`, \\`")}\``,
    );
  }

  // Cookies
  const cookieFns = ["setCookie", "getCookies", "deleteCookies"].filter(has);
  if (cookieFns.length > 0) {
    sections.push(
      `**Cookies**: \`${cookieFns.map((s) => (s === "setCookie" ? "setCookie(name, value, options?)" : s === "getCookies" ? "getCookies(url?)" : "deleteCookies(name?)")).join("\\`, \\`")}\``,
    );
  }

  // Emulation
  const emuFns = ["emulateDevice", "emulateNetwork", "emulateTimezone", "setViewPort", "setLocation"].filter(has);
  if (emuFns.length > 0) {
    sections.push(`**Emulation**: \`${emuFns.map((s) => s + "(...)").join("\\`, \\`")}\``);
  }

  // Other
  const otherParts: string[] = [];
  if (has("evaluate"))
    otherParts.push(
      'evaluate("js") — run JS in the browser page (pass a string; objects auto-stringified to JSON; the last expression is auto-returned)',
    );
  if (has("waitFor")) otherParts.push("waitFor(selectorOrMs)");
  if (has("screenshot")) otherParts.push("screenshot()");
  if (has("accept")) otherParts.push("accept(text?)");
  if (has("dismiss")) otherParts.push("dismiss()");
  otherParts.push("into(selector)", "to(selector)");
  if (has("highlight")) otherParts.push("highlight(selector)");
  if (has("clearHighlights")) otherParts.push("clearHighlights()");
  if (has("attach")) otherParts.push("attach(filePath, to(selector))");
  sections.push(`**Other**: \`${otherParts.join("\\`, \\`")}\``);

  return sections.join("\n\n");
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
