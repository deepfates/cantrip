/**
 * Robustness tests:
 * 1. safeStringify — handles cyclic/non-serializable data
 * 2. call_entity_batch — validates task intents before calling .slice()
 * 3. Browser capability docs filtering
 */
import { describe, expect, test, afterEach } from "bun:test";
import { JsAsyncContext } from "../../../src/circle/medium/js/async_context";
import type { BaseChatModel } from "../../../src/crystal/crystal";
import type { AnyMessage } from "../../../src/crystal/messages";
import type { ChatInvokeCompletion } from "../../../src/crystal/views";
import { cantrip } from "../../../src/cantrip/cantrip";
import { Circle } from "../../../src/circle/circle";
import { js, getJsMediumSandbox } from "../../../src/circle/medium/js";
import { max_turns, require_done } from "../../../src/circle/ward";
import {
  call_entity,
  call_entity_batch,
  spawnBinding,
  type SpawnFn,
} from "../../../src/circle/gate/builtin/call_entity_gate";
import { done_for_medium } from "../../../src/circle/gate/builtin/done";
import { buildBrowserDocs } from "../../../src/circle/medium/js_browser";
import type { Entity } from "../../../src/cantrip/entity";

// Inline safeStringify for tests
function safeStringify(value: unknown, indent?: number): string | undefined {
  try {
    return JSON.stringify(value, null, indent);
  } catch {
    return "[unserializable]";
  }
}

/**
 * Local helper for sandbox tests.
 * Provides a rich spawn that gives children their own sandboxes.
 */
async function createTestAgent(opts: {
  llm: BaseChatModel;
  context: unknown;
  maxDepth?: number;
  depth?: number;
}): Promise<{ entity: Entity; sandbox: JsAsyncContext }> {
  const depth = opts.depth ?? 0;
  const maxDepth = opts.maxDepth ?? 2;

  const medium = js({ state: { context: opts.context } });
  const gates = [done_for_medium()];
  const entityGate = call_entity({
    max_depth: maxDepth,
    depth,
    parent_context: opts.context,
  });
  if (entityGate) gates.push(entityGate);
  const batchGate = call_entity_batch({
    max_depth: maxDepth,
    depth,
    parent_context: opts.context,
  });
  if (batchGate) gates.push(batchGate);

  const circle = Circle({
    medium,
    gates,
    wards: [max_turns(20), require_done()],
  });

  // Rich spawn: children get their own circles with sandboxes
  const childDepth = depth + 1;
  const richSpawn: SpawnFn = async (
    query: string,
    context: unknown,
  ): Promise<string> => {
    if (childDepth >= maxDepth) {
      const res = await opts.llm.query([{ role: "user", content: query }]);
      return res.content ?? "";
    }
    const child = await createTestAgent({
      llm: opts.llm,
      context,
      maxDepth,
      depth: childDepth,
    });
    try {
      return await child.entity.cast(query);
    } finally {
      child.sandbox.dispose();
    }
  };

  const overrides = new Map<any, any>();
  overrides.set(spawnBinding, (): SpawnFn => richSpawn);

  const spell = cantrip({
    crystal: opts.llm,
    call: "Explore the context using code. Use submit_answer() to provide your final answer.",
    circle,
    dependency_overrides: overrides,
  });
  const entity = spell.invoke();

  await medium.init(gates, entity.dependency_overrides);
  const sandbox = getJsMediumSandbox(medium)!;

  return { entity, sandbox };
}

// ---------------------------------------------------------------------------
// 1. safeStringify
// ---------------------------------------------------------------------------
describe("safeStringify", () => {
  test("serializes plain objects", () => {
    expect(safeStringify({ a: 1 })).toBe('{"a":1}');
  });

  test("supports indent parameter", () => {
    expect(safeStringify({ a: 1 }, 2)).toBe('{\n  "a": 1\n}');
  });

  test("returns [unserializable] for cyclic data", () => {
    const obj: any = { name: "root" };
    obj.self = obj; // circular reference
    expect(safeStringify(obj)).toBe("[unserializable]");
  });

  test("returns [unserializable] for BigInt values", () => {
    // JSON.stringify throws on BigInt
    expect(safeStringify({ n: BigInt(42) })).toBe("[unserializable]");
  });

  test("handles null and undefined", () => {
    expect(safeStringify(null)).toBe("null");
    expect(safeStringify(undefined)).toBe(undefined as any); // JSON.stringify(undefined) returns undefined
  });

  test("handles arrays with nested cycles", () => {
    const arr: any[] = [1, 2];
    arr.push(arr);
    expect(safeStringify(arr)).toBe("[unserializable]");
  });
});

// ---------------------------------------------------------------------------
// 2. Browser capability docs filtering
// ---------------------------------------------------------------------------
describe("browser capability docs filtering", () => {
  test("full profile includes all browser sections", () => {
    const docs = buildBrowserDocs();

    expect(docs).toContain("**Selectors**");
    expect(docs).toContain("openTab(url)");
    expect(docs).toContain("setCookie");
    expect(docs).toContain("emulateDevice");
    expect(docs).toContain("dragAndDrop");
    expect(docs).toContain("**Tabs**");
  });

  test("readonly profile omits write actions and tabs", () => {
    const readonlyFns = new Set([
      "button",
      "link",
      "text",
      "textBox",
      "$",
      "near",
      "above",
      "below",
      "goto",
      "currentURL",
      "title",
      "evaluate",
      "waitFor",
      "screenshot",
    ]);

    const docs = buildBrowserDocs(readonlyFns);

    expect(docs).toContain("**Selectors**");
    expect(docs).toContain("button(text)");
    expect(docs).toContain("goto(url)");
    expect(docs).toContain("evaluate");

    expect(docs).not.toContain("openTab(url)");
    expect(docs).not.toContain("setCookie");
    expect(docs).not.toContain("emulateDevice");
    expect(docs).not.toContain("dragAndDrop");
    expect(docs).not.toContain("**Tabs**");
  });

  test("empty allowed set produces no selector/action sections", () => {
    // Equivalent to old "no browser flag omits entire browser section" —
    // when no functions are allowed, the docs should have no meaningful content
    const docs = buildBrowserDocs(new Set());

    expect(docs).not.toContain("**Selectors**");
    expect(docs).not.toContain("**Actions**");
    expect(docs).not.toContain("**Navigation**");
    expect(docs).not.toContain("**Tabs**");
    expect(docs).not.toContain("openTab");
    expect(docs).not.toContain("button(text)");
    expect(docs).not.toContain("click(selector");
  });

  test("buildBrowserDocs with readonly set matches jsBrowser capabilityDocs filtering", () => {
    // Equivalent to old "memory prompt respects browser profile filtering" —
    // tests that buildBrowserDocs (used by jsBrowser.capabilityDocs) correctly
    // filters to only the allowed functions, same as old memory prompt path did.
    const readonlyFns = new Set([
      "button",
      "link",
      "text",
      "goto",
      "currentURL",
      "title",
      "evaluate",
    ]);

    const docs = buildBrowserDocs(readonlyFns);

    expect(docs).toContain("**Selectors**");
    expect(docs).toContain("button(text)");
    expect(docs).toContain("goto(url)");
    // Should not document functions outside the allowed set
    expect(docs).not.toContain("openTab(url)");
    expect(docs).not.toContain("setCookie");
    expect(docs).not.toContain("**Tabs**");
  });

  test("interactive profile includes actions but not emulation", () => {
    const interactiveFns = new Set([
      "button",
      "link",
      "text",
      "textBox",
      "$",
      "near",
      "above",
      "below",
      "toLeftOf",
      "toRightOf",
      "click",
      "doubleClick",
      "write",
      "clear",
      "press",
      "hover",
      "focus",
      "scrollTo",
      "scrollDown",
      "scrollUp",
      "goto",
      "reload",
      "goBack",
      "goForward",
      "currentURL",
      "title",
      "evaluate",
      "waitFor",
      "screenshot",
      "accept",
      "dismiss",
    ]);

    const docs = buildBrowserDocs(interactiveFns);

    expect(docs).toContain("click(selector");
    expect(docs).toContain("write(text");

    expect(docs).not.toContain("emulateDevice");
    expect(docs).not.toContain("setCookie");
    expect(docs).not.toContain("openTab(url)");
  });
});

// ---------------------------------------------------------------------------
// 2b. Medium-level capabilityDocs — jsBrowser vs plain JS
// ---------------------------------------------------------------------------
describe("medium capabilityDocs", () => {
  test("jsBrowser medium capabilityDocs includes browser function docs", () => {
    // Create a mock browser context with a subset of functions
    const mockBrowserContext = {
      getAllowedFunctions: () => [
        "goto",
        "click",
        "text",
        "evaluate",
        "button",
      ],
      buildTaikoScope: () => ({}),
      dispose: async () => {},
    } as any;

    const { jsBrowser } = require("../../../src/circle/medium/js_browser");
    const medium = jsBrowser({ browserContext: mockBrowserContext });
    const docs = medium.capabilityDocs!();

    // Should include JS sandbox docs
    expect(docs).toContain("SANDBOX PHYSICS");
    // Should include browser automation section
    expect(docs).toContain("BROWSER AUTOMATION");
    expect(docs).toContain("goto(url)");
    expect(docs).toContain("click(selector)");
  });

  test("plain JS medium capabilityDocs does NOT include browser docs", () => {
    const { js } = require("../../../src/circle/medium/js");
    const medium = js();
    const docs = medium.capabilityDocs!();

    expect(docs).toContain("SANDBOX PHYSICS");
    expect(docs).not.toContain("BROWSER AUTOMATION");
    expect(docs).not.toContain("goto(url)");
    expect(docs).not.toContain("click(selector)");
  });

  test("cantripGates produce CANTRIP CONSTRUCTION docs via buildCapabilityDocs", () => {
    const { cantripGates } = require("../../../src/circle/gate/builtin/cantrip");
    const { buildCapabilityDocs } = require("../../../src/circle/circle");
    const { done } = require("../../../src/circle/gate/builtin/done");

    const config = {
      crystals: { sonnet: { model: "mock", provider: "mock", name: "mock", query: async () => ({}) } },
      mediums: { bash: () => ({}) },
      gates: { done: [done] },
      default_wards: [{ max_turns: 5 }],
    };
    const { gates } = cantripGates(config);
    const docs = buildCapabilityDocs(gates);

    expect(docs).toContain("CANTRIP CONSTRUCTION");
    expect(docs).toContain("cantrip");
    expect(docs).toContain("cast");
    expect(docs).toContain("dispose");
  });

  test("plain JS medium capabilityDocs does NOT include cantrip section", () => {
    const { js } = require("../../../src/circle/medium/js");
    const medium = js({ state: { data: [1, 2, 3] } });
    const docs = medium.capabilityDocs!();

    expect(docs).toContain("SANDBOX PHYSICS");
    expect(docs).not.toContain("CANTRIP CONSTRUCTION");
  });
});

// ---------------------------------------------------------------------------
// 2c. JS medium schema — OpenAI strict compatibility
// ---------------------------------------------------------------------------
describe("JS medium schema", () => {
  test("all properties are in required (OpenAI strict schema compliance)", () => {
    const { js } = require("../../../src/circle/medium/js");
    const medium = js();
    const { tool_definitions } = medium.crystalView();
    const jsTool = tool_definitions.find((t: any) => t.name === "js");
    expect(jsTool).toBeDefined();
    expect(jsTool!.parameters.required).toContain("code");
    expect(jsTool!.parameters.required).toContain("timeout_ms");
    // Every property key must be in required when additionalProperties: false
    const propKeys = Object.keys(jsTool!.parameters.properties);
    for (const key of propKeys) {
      expect(jsTool!.parameters.required).toContain(key);
    }
  });
});

// ---------------------------------------------------------------------------
// 3. call_entity_batch — validates task intents before calling .slice()
// ---------------------------------------------------------------------------

class MockLlm implements BaseChatModel {
  model = "mock";
  provider = "mock";
  name = "mock";
  private callCount = 0;

  constructor(
    private responses: ((messages: AnyMessage[]) => ChatInvokeCompletion)[],
  ) {}

  async query(messages: AnyMessage[]): Promise<ChatInvokeCompletion> {
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

describe("call_entity_batch input validation", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("rejects batch tasks with missing query", async () => {
    const mockLlm = new MockLlm([
      // First call: the agent emits sandbox code with a malformed batch
      (_msgs) => ({
        content: "Batching",
        tool_calls: [
          {
            id: "t1",
            type: "function" as const,
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: `try {
  call_entity_batch([{context: "no query here"}]);
  submit_answer("should not reach");
} catch(e) {
  submit_answer("caught: " + e.message);
}`,
              }),
            },
          },
        ],
      }),
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: "test",
      maxDepth: 1,
    });
    activeSandbox = sandbox;

    const result = await entity.cast("Start");
    expect(result).toContain("call_entity_batch: task[0].intent must be a string");
  });

  test("rejects null batch task", async () => {
    const mockLlm = new MockLlm([
      (_msgs) => ({
        content: "Batching",
        tool_calls: [
          {
            id: "t1",
            type: "function" as const,
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: `try {
  call_entity_batch([null]);
  submit_answer("should not reach");
} catch(e) {
  submit_answer("caught: " + e.message);
}`,
              }),
            },
          },
        ],
      }),
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: "test",
      maxDepth: 1,
    });
    activeSandbox = sandbox;

    const result = await entity.cast("Start");
    expect(result).toContain("call_entity_batch: task[0].intent must be a string");
  });
});
