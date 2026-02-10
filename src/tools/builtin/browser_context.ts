import { Depends } from "../depends";
import * as taiko from "taiko";

export type BrowserProfile = "full" | "interactive" | "readonly";

type DomainPolicy = {
  allow?: string[];
  deny?: string[];
};

type BrowserOptions = {
  headless?: boolean;
  args?: string[];
  profile?: BrowserProfile;
  historyLimit?: number;
  domainPolicy?: DomainPolicy;
  defaultTimeoutMs?: number;
  recoveryTimeoutMs?: number;
};

type EvalResult = { ok: true; output: string } | { ok: false; error: string };

/**
 * Manages a persistent Taiko browser session.
 * All Taiko functions are available in evaluated code.
 */
export class BrowserContext {
  private static browserOpen = false;
  private static browserRefCount = 0;
  private static sharedBrowserOptions: {
    headless: boolean;
    args: string[];
  } | null = null;

  private disposed = false;
  private defaultTimeoutMs: number;
  private recoveryTimeoutMs: number;
  private profile: BrowserProfile;
  private history: string[] = [];
  private historyLimit: number;
  private domainPolicy?: DomainPolicy;
  private browserOptions: { headless: boolean; args: string[] };

  private constructor(options: {
    defaultTimeoutMs: number;
    recoveryTimeoutMs: number;
    profile: BrowserProfile;
    historyLimit: number;
    domainPolicy?: DomainPolicy;
    browserOptions: { headless: boolean; args: string[] };
  }) {
    this.defaultTimeoutMs = options.defaultTimeoutMs;
    this.recoveryTimeoutMs = options.recoveryTimeoutMs;
    this.profile = options.profile;
    this.historyLimit = options.historyLimit;
    this.domainPolicy = options.domainPolicy;
    this.browserOptions = options.browserOptions;
  }

  /**
   * Creates a new BrowserContext with an open browser.
   */
  static async create(options: BrowserOptions = {}): Promise<BrowserContext> {
    const headless = options.headless ?? true;
    const args = options.args ?? [];
    const profile = options.profile ?? "full";
    const historyLimit = options.historyLimit ?? 50;
    const defaultTimeoutMs = options.defaultTimeoutMs ?? 30000;
    const recoveryTimeoutMs = options.recoveryTimeoutMs ?? 5000;

    if (!BrowserContext.browserOpen) {
      try {
        await taiko.openBrowser({
          headless,
          args: [
            "--no-sandbox",
            "--disable-setuid-sandbox",
            "--disable-dev-shm-usage",
            ...args,
          ],
        });
        BrowserContext.browserOpen = true;
        BrowserContext.sharedBrowserOptions = { headless, args };
      } catch (err: any) {
        if (isBrowserAlreadyOpenError(err)) {
          BrowserContext.browserOpen = true;
          if (!BrowserContext.sharedBrowserOptions) {
            BrowserContext.sharedBrowserOptions = { headless, args };
          }
        } else {
          throw err;
        }
      }
    }

    BrowserContext.browserRefCount += 1;
    const browserOptions = BrowserContext.sharedBrowserOptions ?? {
      headless,
      args,
    };

    return new BrowserContext({
      defaultTimeoutMs,
      recoveryTimeoutMs,
      profile,
      historyLimit,
      domainPolicy: options.domainPolicy,
      browserOptions,
    });
  }

  /**
   * Executes Taiko code in the browser context.
   * All Taiko functions (goto, click, write, etc.) are available.
   */
  async evalCode(
    code: string,
    options: { timeoutMs?: number; resetSession?: boolean } = {},
  ): Promise<EvalResult> {
    if (this.disposed) {
      return { ok: false, error: "BrowserContext is disposed" };
    }

    if (options.resetSession) {
      await this.resetSession();
    }

    const commandResult = await this.handleMetaCommand(code);
    if (commandResult) {
      return commandResult;
    }

    const timeoutMs = options.timeoutMs ?? this.defaultTimeoutMs;

    try {
      // Build the async function that has access to all Taiko functions
      const taikoFunctions = this.getAllowedFunctions();
      const taikoScope = this.buildTaikoScope(taikoFunctions);
      const destructure = `const { ${taikoFunctions.join(", ")} } = taiko;`;

      // Wrap code in async function
      const wrappedCode = `
        ${destructure}
        return (async () => {
          ${code}
        })();
      `;

      // Create function with taiko in scope
      const fn = new Function("taiko", wrappedCode);

      // Execute with timeout
      const result = await Promise.race([
        fn(taikoScope),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error("Execution timeout")), timeoutMs),
        ),
      ]);

      this.recordHistory(code);
      return { ok: true, output: formatOutput(result) };
    } catch (err: any) {
      const errorText = formatError(err);
      if (errorText.toLowerCase().includes("timeout")) {
        await this.recoverFromTimeout();
      }
      return { ok: false, error: errorText };
    }
  }

  /**
   * Exports the recorded history as a runnable Taiko script.
   */
  exportCode(): string {
    const allowed = this.getAllowedFunctions();
    const headerFunctions = ["openBrowser", "closeBrowser", ...allowed];
    const header = `const { ${headerFunctions.join(", ")} } = require('taiko');`;
    const body = this.history
      .map((snippet) => snippet.trim())
      .filter(Boolean)
      .map((snippet) => indent(snippet, 4))
      .join("\n\n");

    const bodyWithFallback = body || indent("// No recorded steps yet.", 4);

    return [
      header,
      "",
      "(async () => {",
      "  try {",
      "    await openBrowser();",
      bodyWithFallback,
      "  } catch (error) {",
      "    console.error(error);",
      "  } finally {",
      "    await closeBrowser();",
      "  }",
      "})();",
      "",
    ].join("\n");
  }

  /**
   * Best-effort session reset to recover from poisoned state.
   */
  async resetSession(): Promise<void> {
    if (this.disposed) return;
    try {
      await taiko.closeBrowser();
    } catch {
      // Ignore close errors
    }

    await taiko.openBrowser({
      headless: this.browserOptions.headless,
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        ...this.browserOptions.args,
      ],
    });
  }

  private async recoverFromTimeout(): Promise<void> {
    try {
      await Promise.race([
        taiko.goto("about:blank"),
        new Promise((_, reject) =>
          setTimeout(
            () => reject(new Error("Recovery timeout")),
            this.recoveryTimeoutMs,
          ),
        ),
      ]);
    } catch {
      // If soft recovery fails, try a full reset.
      await this.resetSession();
    }
  }

  private recordHistory(code: string) {
    const trimmed = code.trim();
    if (!trimmed) return;
    this.history.push(code);
    if (this.history.length > this.historyLimit) {
      this.history.shift();
    }
  }

  private async handleMetaCommand(code: string): Promise<EvalResult | null> {
    const trimmed = code.trim();
    if (trimmed === ".code") {
      return { ok: true, output: this.exportCode() };
    }
    if (trimmed === ".reset") {
      await this.resetSession();
      return { ok: true, output: "Session reset." };
    }
    return null;
  }

  getAllowedFunctions(): string[] {
    const full = getTaikoFunctionList();
    if (this.profile === "full") return full;
    const blocked = new Set<string>();

    // Blocked for interactive and readonly
    [
      "evaluate",
      "intercept",
      "clearIntercept",
      "setCookie",
      "getCookies",
      "deleteCookies",
      "overridePermissions",
      "clearPermissionOverrides",
      "client",
    ].forEach((fn) => blocked.add(fn));

    if (this.profile === "readonly") {
      [
        "click",
        "doubleClick",
        "rightClick",
        "write",
        "clear",
        "press",
        "hover",
        "focus",
        "dragAndDrop",
        "tap",
      ].forEach((fn) => blocked.add(fn));
    }

    return full.filter((fn) => !blocked.has(fn));
  }

  buildTaikoScope(allowed: string[]) {
    const scope: Record<string, any> = {};
    for (const fn of allowed) {
      const original = (taiko as any)[fn];
      if (fn === "goto" || fn === "openTab") {
        scope[fn] = this.wrapNavigation(fn, original);
      } else {
        scope[fn] = original;
      }
    }
    return scope;
  }

  private wrapNavigation(fnName: "goto" | "openTab", original: any) {
    return async (...args: any[]) => {
      const target = args[0];
      if (typeof target === "string") {
        this.assertUrlAllowed(target);
      }
      return original(...args);
    };
  }

  assertUrlAllowed(url: string) {
    if (!this.domainPolicy) return;
    let hostname = "";
    try {
      const parsed = new URL(url);
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
        return;
      }
      hostname = parsed.hostname.toLowerCase();
    } catch {
      return;
    }

    const allow = (this.domainPolicy.allow ?? []).map(normalizeDomain);
    const deny = (this.domainPolicy.deny ?? []).map(normalizeDomain);

    if (deny.some((rule) => matchesDomain(hostname, rule))) {
      throw new Error(`Blocked by domain denylist: ${hostname}`);
    }

    if (
      allow.length > 0 &&
      !allow.some((rule) => matchesDomain(hostname, rule))
    ) {
      throw new Error(`Blocked by domain allowlist: ${hostname}`);
    }
  }

  /**
   * Closes the browser and cleans up resources.
   */
  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    try {
      BrowserContext.browserRefCount = Math.max(
        0,
        BrowserContext.browserRefCount - 1,
      );
      if (BrowserContext.browserRefCount === 0) {
        await taiko.closeBrowser();
        BrowserContext.browserOpen = false;
        BrowserContext.sharedBrowserOptions = null;
      }
    } catch {
      // Ignore errors during cleanup
    }
  }
}

export function getTaikoFunctionList(): string[] {
  return [
    // Browser actions
    "goto",
    "reload",
    "goBack",
    "goForward",
    "currentURL",
    "title",
    "openTab",
    "closeTab",
    "switchTo",
    // Interactions
    "click",
    "doubleClick",
    "rightClick",
    "write",
    "clear",
    "press",
    "hover",
    "focus",
    "scrollTo",
    "scrollDown",
    "scrollUp",
    "scrollLeft",
    "scrollRight",
    "dragAndDrop",
    "tap",
    // Selectors
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
    // Proximity selectors
    "near",
    "above",
    "below",
    "toLeftOf",
    "toRightOf",
    "within",
    // Helpers
    "into",
    "to",
    "waitFor",
    "evaluate",
    "intercept",
    "clearIntercept",
    "screenshot",
    "highlight",
    "clearHighlights",
    // Dialog handlers
    "alert",
    "prompt",
    "confirm",
    "accept",
    "dismiss",
    // Config
    "setConfig",
    "getConfig",
    // Other
    "emulateDevice",
    "emulateNetwork",
    "emulateTimezone",
    "setViewPort",
    "setCookie",
    "getCookies",
    "deleteCookies",
    "setLocation",
    "overridePermissions",
    "clearPermissionOverrides",
    "client",
  ];
}

function indent(text: string, spaces: number): string {
  const pad = " ".repeat(spaces);
  return text
    .split("\n")
    .map((line) => (line.length ? `${pad}${line}` : line))
    .join("\n");
}

function normalizeDomain(domain: string): string {
  return domain.trim().toLowerCase();
}

function matchesDomain(hostname: string, rule: string): boolean {
  if (!rule) return false;
  if (rule.startsWith("*.")) {
    const suffix = rule.slice(2);
    return hostname === suffix || hostname.endsWith(`.${suffix}`);
  }
  return hostname === rule || hostname.endsWith(`.${rule}`);
}

function formatOutput(value: unknown): string {
  if (value === undefined) return "undefined";
  if (value === null) return "null";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return safeStringify(value) ?? String(value);
}

function formatError(err: unknown): string {
  if (err instanceof Error) {
    return err.message;
  }
  if (typeof err === "string") {
    return err;
  }
  return String(err);
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
          return { name: val.name, message: val.message };
        }
        return val;
      },
      2,
    );
  } catch {
    return null;
  }
}

function isBrowserAlreadyOpenError(err: unknown): boolean {
  const message =
    err instanceof Error ? err.message : typeof err === "string" ? err : "";
  return (
    message.includes("browser instance open") ||
    message.includes("cannot be called again")
  );
}

// --- Dependency Injection ---

/**
 * Shared dependency for BrowserContext.
 * Use this as a key in dependency_overrides Map.
 */
export const getBrowserContext = new Depends<BrowserContext>(
  function getBrowserContext() {
    throw new Error(
      "BrowserContext not provided. Use dependency_overrides: new Map([[getBrowserContext, () => ctx]])",
    );
  },
);

export const getBrowserContextInteractive = new Depends<BrowserContext>(
  function getBrowserContextInteractive() {
    throw new Error(
      "BrowserContext (interactive) not provided. Use dependency_overrides: new Map([[getBrowserContextInteractive, () => ctx]])",
    );
  },
);

export const getBrowserContextReadonly = new Depends<BrowserContext>(
  function getBrowserContextReadonly() {
    throw new Error(
      "BrowserContext (readonly) not provided. Use dependency_overrides: new Map([[getBrowserContextReadonly, () => ctx]])",
    );
  },
);
