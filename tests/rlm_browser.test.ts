import { describe, expect, test, afterEach } from "bun:test";
import { createRlmAgent } from "../src/circle/recipe/rlm";
import { JsAsyncContext } from "../src/circle/medium/js/async_context";
import { HandleTable, describeArg } from "../src/circle/recipe/rlm_tools";
import type { BaseChatModel } from "../src/crystal/crystal";
import type { AnyMessage } from "../src/crystal/messages";
import type { ChatInvokeCompletion } from "../src/crystal/views";
import type { BrowserContext } from "../src/circle/medium/browser/context";

class MockLlm implements BaseChatModel {
  model = "mock";
  provider = "mock";
  name = "mock";
  private callCount = 0;

  constructor(
    private responses: ((messages: AnyMessage[]) => ChatInvokeCompletion)[],
  ) {}

  async ainvoke(messages: AnyMessage[]): Promise<ChatInvokeCompletion> {
    const idx = Math.min(this.callCount, this.responses.length - 1);
    this.callCount++;
    const res = this.responses[idx](messages);
    return {
      ...res,
      usage: res.usage ?? {
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
      },
    };
  }
}

/** Helper to create a mock LLM response that executes JS code */
function jsResponse(code: string, id = "tc1") {
  return () => ({
    content: "executing",
    tool_calls: [
      {
        id,
        type: "function" as const,
        function: {
          name: "js",
          arguments: JSON.stringify({ code }),
        },
      },
    ],
  });
}

/**
 * Creates a mock BrowserContext with fake Taiko functions for testing the handle pattern.
 *
 * The mock tracks all function calls and returns fake ElementWrapper-like objects
 * (class instances that can't be serialized by valueToHandle — just like real Taiko).
 */
function mockBrowserContext(options?: {
  allowedFunctions?: string[];
}): BrowserContext & { calls: Array<{ fn: string; args: any[] }> } {
  const calls: Array<{ fn: string; args: any[] }> = [];

  // Simulate ElementWrapper — a class instance (not a plain object)
  class FakeElementWrapper {
    constructor(
      public readonly selectorType: string,
      public readonly selectorArg: string,
    ) {}
    async text() {
      return `text of ${this.selectorType}("${this.selectorArg}")`;
    }
    async exists() {
      return true;
    }
    async isVisible() {
      return true;
    }
    async value() {
      return `value of ${this.selectorType}("${this.selectorArg}")`;
    }
    async attribute(name: string) {
      return `attr-${name}`;
    }
    get description() {
      return `${this.selectorType}("${this.selectorArg}")`;
    }
  }

  // Simulate RelativeSearchElement
  class FakeRelativeSearch {
    constructor(
      public readonly proximity: string,
      public readonly reference: any,
    ) {}
  }

  // Build a fake Taiko scope
  const selectorFns = [
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
  ];

  const proximityFns = [
    "near",
    "above",
    "below",
    "toLeftOf",
    "toRightOf",
    "within",
  ];

  const scope: Record<string, any> = {};

  // Selector functions return FakeElementWrapper instances
  for (const name of selectorFns) {
    scope[name] = (arg: string, ...rest: any[]) => {
      calls.push({ fn: name, args: [arg, ...rest] });
      return new FakeElementWrapper(name, arg ?? "");
    };
  }

  // Proximity functions accept an element and return FakeRelativeSearch
  for (const name of proximityFns) {
    scope[name] = (ref: any, ...rest: any[]) => {
      calls.push({ fn: name, args: [ref, ...rest] });
      return new FakeRelativeSearch(name, ref);
    };
  }

  // Action functions
  scope.click = async (selector: any, ...args: any[]) => {
    calls.push({ fn: "click", args: [selector, ...args] });
  };
  scope.doubleClick = async (selector: any, ...args: any[]) => {
    calls.push({ fn: "doubleClick", args: [selector, ...args] });
  };
  scope.rightClick = async (selector: any, ...args: any[]) => {
    calls.push({ fn: "rightClick", args: [selector, ...args] });
  };
  scope.write = async (text: string, into?: any, opts?: any) => {
    calls.push({ fn: "write", args: [text, into, opts] });
  };
  scope.clear = async (selector: any) => {
    calls.push({ fn: "clear", args: [selector] });
  };
  scope.press = async (key: string, opts?: any) => {
    calls.push({ fn: "press", args: [key, opts] });
  };
  scope.hover = async (selector: any) => {
    calls.push({ fn: "hover", args: [selector] });
  };
  scope.focus = async (selector: any) => {
    calls.push({ fn: "focus", args: [selector] });
  };
  scope.scrollTo = async (selector: any) => {
    calls.push({ fn: "scrollTo", args: [selector] });
  };
  scope.scrollDown = async (px?: number) => {
    calls.push({ fn: "scrollDown", args: [px] });
  };
  scope.scrollUp = async (px?: number) => {
    calls.push({ fn: "scrollUp", args: [px] });
  };
  scope.tap = async (selector: any) => {
    calls.push({ fn: "tap", args: [selector] });
  };

  // Navigation functions return primitives
  scope.goto = async (url: string) => {
    calls.push({ fn: "goto", args: [url] });
    return { url, status: 200 };
  };
  scope.reload = async () => {
    calls.push({ fn: "reload", args: [] });
  };
  scope.goBack = async () => {
    calls.push({ fn: "goBack", args: [] });
  };
  scope.goForward = async () => {
    calls.push({ fn: "goForward", args: [] });
  };
  scope.currentURL = async () => {
    calls.push({ fn: "currentURL", args: [] });
    return "https://example.com";
  };
  scope.title = async () => {
    calls.push({ fn: "title", args: [] });
    return "Example Domain";
  };

  // Evaluation
  scope.evaluate = async (expr: any) => {
    calls.push({ fn: "evaluate", args: [expr] });
    return "eval-result";
  };

  // Waiting
  scope.waitFor = async (selectorOrMs: any) => {
    calls.push({ fn: "waitFor", args: [selectorOrMs] });
  };

  // Screenshot
  scope.screenshot = async (opts?: any) => {
    calls.push({ fn: "screenshot", args: [opts] });
    return "/tmp/screenshot.png";
  };

  // Dialogs
  scope.accept = async (text?: string) => {
    calls.push({ fn: "accept", args: [text] });
  };
  scope.dismiss = async () => {
    calls.push({ fn: "dismiss", args: [] });
  };

  // Tab management
  scope.openTab = async (url: string) => {
    calls.push({ fn: "openTab", args: [url] });
  };
  scope.closeTab = async (url?: string) => {
    calls.push({ fn: "closeTab", args: [url] });
  };
  scope.switchTo = async (urlOrTitle: any) => {
    calls.push({ fn: "switchTo", args: [urlOrTitle] });
  };

  // Drag and drop
  scope.dragAndDrop = async (source: any, target: any) => {
    calls.push({ fn: "dragAndDrop", args: [source, target] });
  };

  // Cookies
  scope.setCookie = async (name: string, value: string, opts?: any) => {
    calls.push({ fn: "setCookie", args: [name, value, opts] });
  };
  scope.getCookies = async (url?: string) => {
    calls.push({ fn: "getCookies", args: [url] });
    return [{ name: "session", value: "abc123", domain: "example.com" }];
  };
  scope.deleteCookies = async (name?: string, opts?: any) => {
    calls.push({ fn: "deleteCookies", args: [name, opts] });
  };

  // Emulation
  scope.emulateDevice = async (device: string) => {
    calls.push({ fn: "emulateDevice", args: [device] });
  };
  scope.emulateNetwork = async (type: string) => {
    calls.push({ fn: "emulateNetwork", args: [type] });
  };
  scope.emulateTimezone = async (tz: string) => {
    calls.push({ fn: "emulateTimezone", args: [tz] });
  };
  scope.setViewPort = async (opts: any) => {
    calls.push({ fn: "setViewPort", args: [opts] });
  };
  scope.setLocation = async (opts: any) => {
    calls.push({ fn: "setLocation", args: [opts] });
  };

  // Permissions
  scope.overridePermissions = async (origin: string, perms: any) => {
    calls.push({ fn: "overridePermissions", args: [origin, perms] });
  };
  scope.clearPermissionOverrides = async (origin?: string) => {
    calls.push({ fn: "clearPermissionOverrides", args: [origin] });
  };

  // Network
  scope.clearIntercept = async (url?: string) => {
    calls.push({ fn: "clearIntercept", args: [url] });
  };

  // Visual/Debug
  scope.highlight = async (selector: any) => {
    calls.push({ fn: "highlight", args: [selector] });
  };
  scope.clearHighlights = async () => {
    calls.push({ fn: "clearHighlights", args: [] });
  };
  scope.setConfig = async (opts: any) => {
    calls.push({ fn: "setConfig", args: [opts] });
  };
  scope.getConfig = async (key?: string) => {
    calls.push({ fn: "getConfig", args: [key] });
    return key ? 3000 : { retryTimeout: 3000 };
  };

  // File upload
  scope.attach = async (filePath: string, to: any) => {
    calls.push({ fn: "attach", args: [filePath, to] });
  };

  // Taiko aliases
  scope.into = (x: any) => x;
  scope.to = (x: any) => x;

  const allowed = options?.allowedFunctions ?? Object.keys(scope);

  return {
    calls,
    getAllowedFunctions: () => allowed,
    buildTaikoScope: (fns: string[]) => {
      const filtered: Record<string, any> = {};
      for (const fn of fns) {
        if (scope[fn]) filtered[fn] = scope[fn];
      }
      return filtered;
    },
    assertUrlAllowed: (_url: string) => {
      // no-op for tests
    },
    // Stubs for BrowserContext interface
    evalCode: async () => ({ ok: true as const, output: "" }),
    exportCode: () => "",
    resetSession: async () => {},
    dispose: async () => {},
  } as any;
}

describe("RLM browser handle pattern", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("selector functions return handle objects with __h and desc", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'var btn = button("Submit"); submit_answer(JSON.stringify(btn));',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    const parsed = JSON.parse(result);
    expect(parsed.__h).toBeNumber();
    expect(parsed.kind).toBe("taiko_handle");
    expect(parsed.desc).toContain("button");
    expect(parsed.desc).toContain("Submit");
  });

  test("click resolves handle and calls Taiko function", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'var btn = button("Submit"); click(btn); submit_answer("clicked");',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("clicked");
    // Verify the mock Taiko click was called with the real FakeElementWrapper
    const clickCall = browserCtx.calls.find((c) => c.fn === "click");
    expect(clickCall).toBeDefined();
    expect(clickCall!.args[0]).toHaveProperty("selectorType", "button");
  });

  test("proximity selectors compose handles", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var btn = button("Submit");',
          'var txt = text("Login");',
          "click(btn, near(txt));",
          'submit_answer("composed");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("composed");
    // near() should have been called with real FakeElementWrapper
    const nearCall = browserCtx.calls.find((c) => c.fn === "near");
    expect(nearCall).toBeDefined();
    expect(nearCall!.args[0]).toHaveProperty("selectorType", "text");
    // click should have been called with both resolved args
    const clickCall = browserCtx.calls.find((c) => c.fn === "click");
    expect(clickCall).toBeDefined();
    expect(clickCall!.args[0]).toHaveProperty("selectorType", "button");
    // Second arg should be the RelativeSearchElement from near()
    expect(clickCall!.args[1]).toHaveProperty("proximity", "near");
  });

  test("string shorthand works for click", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse('click("Submit"); submit_answer("clicked string");'),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("clicked string");
    // String is passed directly to Taiko's click (which accepts strings natively)
    const clickCall = browserCtx.calls.find((c) => c.fn === "click");
    expect(clickCall).toBeDefined();
    expect(clickCall!.args[0]).toBe("Submit");
  });

  test("elem_text returns string from handle", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'var btn = button("Submit"); var t = elem_text(btn); submit_answer(t);',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toContain("button");
    expect(result).toContain("Submit");
  });

  test("elem_exists returns boolean from handle", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'var btn = button("Submit"); var e = elem_exists(btn); submit_answer(String(e));',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("true");
  });

  test("invalid handle throws clear error", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      // First call: try to click with a fake handle
      jsResponse('click({__h: 999, kind: "taiko_handle", desc: "fake"});'),
      // Second call: LLM recovers after error
      jsResponse('submit_answer("recovered");', "tc2"),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("recovered");
  });

  test("navigation functions return primitives", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'goto("https://example.com");',
          "var url = currentURL();",
          "var t = title();",
          'submit_answer(url + " - " + t);',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("https://example.com - Example Domain");
  });

  test("write accepts text and selector handle", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var field = textBox("Username");',
          'write("admin", field);',
          'submit_answer("written");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("written");
    const writeCall = browserCtx.calls.find((c) => c.fn === "write");
    expect(writeCall).toBeDefined();
    expect(writeCall!.args[0]).toBe("admin");
    expect(writeCall!.args[1]).toHaveProperty("selectorType", "textBox");
  });

  test("data flows naturally between context and browser functions", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          "var url = context.targetUrl;",
          "goto(url);",
          "var t = title();",
          "submit_answer(t);",
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: { targetUrl: "https://example.com" },
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("Example Domain");
    const gotoCall = browserCtx.calls.find((c) => c.fn === "goto");
    expect(gotoCall).toBeDefined();
    expect(gotoCall!.args[0]).toBe("https://example.com");
  });

  test("browser functions NOT registered when browserContext is absent", async () => {
    const mockLlm = new MockLlm([
      // Try calling button() — should error
      jsResponse('var btn = button("Submit");'),
      // Recover
      jsResponse('submit_answer("no browser");', "tc2"),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("no browser");
  });

  test("system prompt includes browser docs when browserContext is provided", async () => {
    const browserCtx = mockBrowserContext();

    let capturedSystemPrompt = "";
    const mockLlm = new MockLlm([
      (msgs) => {
        const systemMsg = msgs.find((m) => m.role === "system");
        if (systemMsg && typeof systemMsg.content === "string") {
          capturedSystemPrompt = systemMsg.content;
        }
        return {
          content: "Done",
          tool_calls: [
            {
              id: "tc1",
              type: "function" as const,
              function: {
                name: "js",
                arguments: JSON.stringify({
                  code: 'submit_answer("done");',
                }),
              },
            },
          ],
        };
      },
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    await entity.turn("test");
    expect(capturedSystemPrompt).toContain("button(");
    expect(capturedSystemPrompt).toContain("click(");
    expect(capturedSystemPrompt).toContain("goto(");
    expect(capturedSystemPrompt).toContain(".text()");
    expect(capturedSystemPrompt).toContain("into(");
  });

  test("system prompt does NOT include browser docs when absent", async () => {
    let capturedSystemPrompt = "";
    const mockLlm = new MockLlm([
      (msgs) => {
        const systemMsg = msgs.find((m) => m.role === "system");
        if (systemMsg && typeof systemMsg.content === "string") {
          capturedSystemPrompt = systemMsg.content;
        }
        return {
          content: "Done",
          tool_calls: [
            {
              id: "tc1",
              type: "function" as const,
              function: {
                name: "js",
                arguments: JSON.stringify({
                  code: 'submit_answer("done");',
                }),
              },
            },
          ],
        };
      },
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
    });
    activeSandbox = sandbox;

    await entity.turn("test");
    expect(capturedSystemPrompt).not.toContain("button(");
    expect(capturedSystemPrompt).not.toContain(".text()");
    expect(capturedSystemPrompt).not.toContain("into(");
  });

  test("browser functions propagate to child agents", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      (msgs) => {
        const last = msgs[msgs.length - 1];
        if (last.content === "Start") {
          return {
            content: "Delegating",
            tool_calls: [
              {
                id: "p1",
                type: "function" as const,
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: 'var r = llm_query("Use the browser"); submit_answer(r);',
                  }),
                },
              },
            ],
          };
        }
        // Child agent should have browser functions available
        if (
          typeof last.content === "string" &&
          last.content.includes("Use the browser")
        ) {
          return {
            content: "Using browser",
            tool_calls: [
              {
                id: "c1",
                type: "function" as const,
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var t = title(); submit_answer(t);",
                  }),
                },
              },
            ],
          };
        }
        return { content: "?", tool_calls: [] };
      },
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test data",
      maxDepth: 1,
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("Start");
    expect(result).toBe("Example Domain");
  });
});

// ---------------------------------------------------------------------------
// Transparent wrapper tests — selectors return objects with callable methods
// ---------------------------------------------------------------------------

describe("RLM browser transparent wrappers", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("button('Submit').text() works as a single expression", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse('var t = button("Submit").text(); submit_answer(t);'),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toContain("Submit");
  });

  test("selector .exists() returns boolean", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'var e = button("Submit").exists(); submit_answer(String(e));',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("true");
  });

  test("selector .value() returns string", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse('var v = textBox("Email").value(); submit_answer(v);'),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toContain("textBox");
    expect(result).toContain("Email");
  });

  test("selector .isVisible() returns boolean", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse('var v = link("Home").isVisible(); submit_answer(String(v));'),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("true");
  });

  test("selector .attribute(name) returns string", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'var a = button("Submit").attribute("class"); submit_answer(a);',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("attr-class");
  });

  test("wrapped handle still works with click() and other actions", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var btn = button("Submit");',
          "var t = btn.text();", // method call
          "click(btn);", // pass to action
          "submit_answer(t);",
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toContain("Submit");
    // click should have resolved the handle correctly
    const clickCall = browserCtx.calls.find((c) => c.fn === "click");
    expect(clickCall).toBeDefined();
    expect(clickCall!.args[0]).toHaveProperty("selectorType", "button");
  });

  test("proximity wrappers also have methods", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var txt = text("Login");',
          "var n = near(txt);",
          // near() returns a wrapped handle too, but RelativeSearchElement
          // won't have .text() — it should still have __h for passing to actions
          'var btn = button("OK");',
          "click(btn, n);",
          'submit_answer("composed");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("composed");
    // The click should have resolved both the button handle and the near handle
    const clickCall = browserCtx.calls.find((c) => c.fn === "click");
    expect(clickCall).toBeDefined();
    expect(clickCall!.args[0]).toHaveProperty("selectorType", "button");
    expect(clickCall!.args[1]).toHaveProperty("proximity", "near");
  });

  test("into() is available and passes through handles", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var field = textBox("Email");',
          'write("user@test.com", into(field));',
          'submit_answer("written");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("written");
    const writeCall = browserCtx.calls.find((c) => c.fn === "write");
    expect(writeCall).toBeDefined();
    expect(writeCall!.args[1]).toHaveProperty("selectorType", "textBox");
  });

  test("method call on invalid/expired handle gives clear error", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var fake = {__h: 999, kind: "taiko_handle", desc: "fake"};',
          // Forged handles (not created by wrapHandle) won't have methods
          'var t = fake.text ? "has method" : "no method";',
          "submit_answer(t);",
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    // Forged handles won't have methods (they weren't created by wrapHandle),
    // so it should say "no method"
    expect(result).toBe("no method");
  });

  test("chained expression: text('Price').text() returns content", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse('submit_answer(text("Price").text());'),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toContain("Price");
  });

  test("evaluate(string) runs expression in browser page", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'var result = evaluate("document.body.innerText"); submit_answer(result);',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("eval-result");
    // Verify evaluate was called with a function, not the raw string
    const evalCall = browserCtx.calls.find((c) => c.fn === "evaluate");
    expect(evalCall).toBeDefined();
    expect(typeof evalCall!.args[0]).toBe("function");
    // The function body should contain the expression
    expect(evalCall!.args[0].toString()).toContain("document.body.innerText");
  });

  test("elem_text still works as backward compat", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse('var btn = button("Submit"); submit_answer(elem_text(btn));'),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toContain("Submit");
  });
});

// ---------------------------------------------------------------------------
// HandleTable unit tests
// ---------------------------------------------------------------------------

describe("HandleTable", () => {
  test("create returns handle with incrementing IDs", () => {
    const table = new HandleTable();
    const h1 = table.create({ fake: "obj1" }, 'button("A")');
    const h2 = table.create({ fake: "obj2" }, 'text("B")');

    expect(h1.__h).toBe(1);
    expect(h2.__h).toBe(2);
    expect(h1.kind).toBe("taiko_handle");
    expect(h1.desc).toBe('button("A")');
    expect(h2.desc).toBe('text("B")');
  });

  test("resolve returns the real object for a valid handle", () => {
    const table = new HandleTable();
    const realObj = { selectorType: "button", text: "Submit" };
    const handle = table.create(realObj, 'button("Submit")');

    const resolved = table.resolve(handle.__h);
    expect(resolved).toBe(realObj); // same reference
  });

  test("resolve throws for invalid handle ID", () => {
    const table = new HandleTable();
    expect(() => table.resolve(999)).toThrow("Invalid handle #999");
  });

  test("resolveArg passes through strings", () => {
    const table = new HandleTable();
    expect(table.resolveArg("hello")).toBe("hello");
  });

  test("resolveArg passes through numbers", () => {
    const table = new HandleTable();
    expect(table.resolveArg(42)).toBe(42);
  });

  test("resolveArg passes through null and undefined", () => {
    const table = new HandleTable();
    expect(table.resolveArg(null)).toBe(null);
    expect(table.resolveArg(undefined)).toBe(undefined);
  });

  test("resolveArg resolves handle objects", () => {
    const table = new HandleTable();
    const realObj = { type: "element" };
    const handle = table.create(realObj, "test");

    expect(table.resolveArg(handle)).toBe(realObj);
  });

  test("resolveArg throws for forged handle with unknown ID", () => {
    const table = new HandleTable();
    const forged = { __h: 42, kind: "taiko_handle", desc: "forged" };
    expect(() => table.resolveArg(forged)).toThrow("Invalid handle #42");
  });

  test("resolveArg passes through plain objects without __h", () => {
    const table = new HandleTable();
    const opts = { force: true, timeout: 5000 };
    expect(table.resolveArg(opts)).toBe(opts);
  });

  test("clear resets the table and ID counter", () => {
    const table = new HandleTable();
    table.create({ a: 1 }, "first");
    table.create({ b: 2 }, "second");

    table.clear();

    // Old handles should be invalid
    expect(() => table.resolve(1)).toThrow("Invalid handle #1");

    // New handles should start from 1 again
    const h = table.create({ c: 3 }, "third");
    expect(h.__h).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// describeArg unit tests
// ---------------------------------------------------------------------------

describe("describeArg", () => {
  test("formats strings with quotes", () => {
    expect(describeArg("Submit")).toBe('"Submit"');
  });

  test("formats numbers and booleans", () => {
    expect(describeArg(42)).toBe("42");
    expect(describeArg(true)).toBe("true");
  });

  test("formats null and undefined", () => {
    expect(describeArg(null)).toBe("null");
    expect(describeArg(undefined)).toBe("undefined");
  });

  test("formats handle objects using desc", () => {
    const handle = { __h: 1, kind: "taiko_handle", desc: 'button("OK")' };
    expect(describeArg(handle)).toBe('button("OK")');
  });

  test("formats plain objects as JSON", () => {
    expect(describeArg({ force: true })).toBe('{"force":true}');
  });
});

// ---------------------------------------------------------------------------
// Sandbox-level edge case tests
// ---------------------------------------------------------------------------

describe("RLM browser edge cases", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("multiple selectors get distinct handle IDs", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var a = button("A");',
          'var b = button("B");',
          'var c = text("C");',
          "submit_answer(JSON.stringify([a.__h, b.__h, c.__h]));",
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    const ids = JSON.parse(result);
    expect(ids).toHaveLength(3);
    // All IDs should be unique
    expect(new Set(ids).size).toBe(3);
  });

  test("isHandle shim is available in sandbox", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var btn = button("Submit");',
          "var results = [",
          "  isHandle(btn),",
          '  isHandle("string"),',
          "  isHandle(42),",
          "  isHandle(null),",
          "  isHandle({regular: true})",
          "];",
          "submit_answer(JSON.stringify(results));",
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    const results = JSON.parse(result);
    expect(results).toEqual([true, false, false, false, false]);
  });

  test("handles survive across multiple js tool calls", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      // First call: create a selector and store it
      jsResponse('var btn = button("Submit");'),
      // Second call: use the stored selector
      (msgs: any) => ({
        content: "using stored selector",
        tool_calls: [
          {
            id: "tc2",
            type: "function" as const,
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: 'click(btn); submit_answer("clicked stored");',
              }),
            },
          },
        ],
      }),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("clicked stored");
    // Verify click was called
    const clickCall = browserCtx.calls.find((c) => c.fn === "click");
    expect(clickCall).toBeDefined();
  });

  test("elem_text on a string argument throws helpful error", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'try { elem_text("raw string"); } catch(e) { submit_answer(e.message); }',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toContain("requires a selector handle");
  });
});

// ---------------------------------------------------------------------------
// Full Taiko API surface tests
// ---------------------------------------------------------------------------

describe("RLM browser full API surface", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("openTab opens a new tab with URL", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'openTab("https://example.com/page2"); submit_answer("opened");',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("opened");
    const call = browserCtx.calls.find((c) => c.fn === "openTab");
    expect(call).toBeDefined();
    expect(call!.args[0]).toBe("https://example.com/page2");
  });

  test("switchTo and closeTab work", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'switchTo("Example Domain");',
          "closeTab();",
          'submit_answer("switched and closed");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("switched and closed");
    expect(browserCtx.calls.find((c) => c.fn === "switchTo")).toBeDefined();
    expect(browserCtx.calls.find((c) => c.fn === "closeTab")).toBeDefined();
  });

  test("dragAndDrop resolves both handle arguments", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var src = text("Drag me");',
          'var tgt = text("Drop here");',
          "dragAndDrop(src, tgt);",
          'submit_answer("dragged");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("dragged");
    const call = browserCtx.calls.find((c) => c.fn === "dragAndDrop");
    expect(call).toBeDefined();
    expect(call!.args[0]).toHaveProperty("selectorType", "text");
    expect(call!.args[1]).toHaveProperty("selectorType", "text");
  });

  test("getCookies returns serializable array", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        "var cookies = getCookies(); submit_answer(JSON.stringify(cookies));",
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    const cookies = JSON.parse(result);
    expect(cookies).toBeArray();
    expect(cookies[0].name).toBe("session");
  });

  test("setCookie and deleteCookies work", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'setCookie("token", "xyz", {domain: "example.com"});',
          'deleteCookies("token");',
          'submit_answer("cookies managed");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("cookies managed");
    expect(browserCtx.calls.find((c) => c.fn === "setCookie")).toBeDefined();
    expect(
      browserCtx.calls.find((c) => c.fn === "deleteCookies"),
    ).toBeDefined();
  });

  test("emulateDevice passes through device string", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse('emulateDevice("iPhone X"); submit_answer("emulated");'),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("emulated");
    const call = browserCtx.calls.find((c) => c.fn === "emulateDevice");
    expect(call).toBeDefined();
    expect(call!.args[0]).toBe("iPhone X");
  });

  test("highlight resolves selector handle", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        'var btn = button("Submit"); highlight(btn); submit_answer("highlighted");',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("highlighted");
    const call = browserCtx.calls.find((c) => c.fn === "highlight");
    expect(call).toBeDefined();
    expect(call!.args[0]).toHaveProperty("selectorType", "button");
  });

  test("to() works as alias for into()", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var field = textBox("Email");',
          'write("user@test.com", to(field));',
          'submit_answer("written with to");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("written with to");
    const writeCall = browserCtx.calls.find((c) => c.fn === "write");
    expect(writeCall).toBeDefined();
    expect(writeCall!.args[1]).toHaveProperty("selectorType", "textBox");
  });

  test("attach resolves selector for file upload target", async () => {
    const browserCtx = mockBrowserContext();

    const mockLlm = new MockLlm([
      jsResponse(
        [
          'var field = fileField("Upload");',
          'attach("/tmp/file.pdf", to(field));',
          'submit_answer("attached");',
        ].join("\n"),
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toBe("attached");
    const call = browserCtx.calls.find((c) => c.fn === "attach");
    expect(call).toBeDefined();
    expect(call!.args[0]).toBe("/tmp/file.pdf");
    expect(call!.args[1]).toHaveProperty("selectorType", "fileField");
  });

  test("cookie functions blocked for restricted profiles", async () => {
    // Simulate interactive profile by excluding cookie functions
    const browserCtx = mockBrowserContext({
      allowedFunctions: [
        "goto",
        "click",
        "button",
        "text",
        "title",
        "currentURL",
      ],
    });

    const mockLlm = new MockLlm([
      // Try calling getCookies — should error since not registered
      jsResponse(
        'try { getCookies(); } catch(e) { submit_answer("blocked: " + e.message); }',
      ),
    ]);

    const { entity, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "test",
      browserContext: browserCtx,
    });
    activeSandbox = sandbox;

    const result = await entity.turn("test");
    expect(result).toContain("blocked");
  });
});
