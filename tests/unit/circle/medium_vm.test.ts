import { describe, expect, test, afterEach } from "bun:test";

import { Circle } from "../../../src/circle/circle";
import type { Circle as CircleType } from "../../../src/circle/circle";
import { max_turns } from "../../../src/circle/ward";
import { vm } from "../../../src/circle/medium/vm";
import { done_for_medium } from "../../../src/circle/gate/builtin/done";
import { gate } from "../../../src/circle/gate/decorator";
import type { AssistantMessage } from "../../../src/crystal/messages";

// ── Helpers ──────────────────────────────────────────────────────────

function makeVmToolCall(code: string, id = "call_1"): AssistantMessage {
  return {
    role: "assistant",
    content: null,
    tool_calls: [
      {
        id,
        type: "function",
        function: {
          name: "vm",
          arguments: JSON.stringify({ code }),
        },
      },
    ],
  };
}

// ── Tests ────────────────────────────────────────────────────────────

describe("Circle with VM medium", () => {
  let circle: CircleType | null = null;

  afterEach(async () => {
    if (circle?.dispose) await circle.dispose();
    circle = null;
  });

  test("auto-injects done_for_medium when medium present and no done gate", () => {
    circle = Circle({
      medium: vm(),
      wards: [max_turns(10)],
    });
    expect(circle.hasMedium).toBe(true);
    expect(circle.gates).toHaveLength(1);
    expect(circle.gates[0].name).toBe("done");
  });

  test("crystalView returns vm tool with required tool_choice", () => {
    circle = Circle({
      medium: vm(),
      wards: [max_turns(10)],
    });
    const view = circle.crystalView();
    expect(view.tool_definitions).toHaveLength(1);
    expect(view.tool_definitions[0].name).toBe("vm");
    expect(view.tool_choice).toEqual({ type: "tool", name: "vm" });
  });

  test("execute runs code and returns metadata", async () => {
    circle = Circle({
      medium: vm({ state: { context: { answer: 42 } } }),
      wards: [max_turns(10)],
    });

    const utterance = makeVmToolCall("JSON.stringify(context)");
    const result = await circle.execute(utterance, {});

    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].role).toBe("tool");
    expect(result.done).toBeUndefined();
    expect(result.messages[0].content).toContain("[Result:");
  });

  test("execute handles submit_answer termination", async () => {
    circle = Circle({
      medium: vm({ state: { context: "hello" } }),
      gates: [done_for_medium()],
      wards: [max_turns(10)],
    });

    const utterance = makeVmToolCall('await submit_answer("the answer is 42")');
    const result = await circle.execute(utterance, {});

    expect(result.done).toBe("the answer is 42");
    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].content).toContain("Task completed");
  });

  test("state persists across execute calls (sync — var)", async () => {
    circle = Circle({
      medium: vm({ state: { context: [1, 2, 3] } }),
      gates: [done_for_medium()],
      wards: [max_turns(10)],
    });

    // First call: set a variable with var (sync path — persists at context level)
    const r1 = await circle.execute(makeVmToolCall("var total = context.reduce((a, b) => a + b, 0)"), {});
    expect(r1.done).toBeUndefined();

    // Second call: var persists, use it
    const r2 = await circle.execute(makeVmToolCall("total"), {});
    expect(r2.messages[0].content).toContain("6");
  });

  test("state persists across execute calls (async — globalThis)", async () => {
    circle = Circle({
      medium: vm({ state: { context: [1, 2, 3] } }),
      gates: [done_for_medium()],
      wards: [max_turns(10)],
    });

    // First call: async path — must use globalThis for persistence
    const r1 = await circle.execute(makeVmToolCall("globalThis.total = await Promise.resolve(context.reduce((a, b) => a + b, 0))"), {});
    expect(r1.done).toBeUndefined();

    // Second call: globalThis persists
    const r2 = await circle.execute(makeVmToolCall("await submit_answer(String(globalThis.total))"), {});
    expect(r2.done).toBe("6");
  });

  test("arrow functions work", async () => {
    circle = Circle({
      medium: vm(),
      wards: [max_turns(10)],
    });

    const utterance = makeVmToolCall("[1,2,3].map(x => x * 2).join(',')");
    const result = await circle.execute(utterance, {});

    expect(result.messages[0].content).toContain("2,4,6");
  });

  test("async/await works", async () => {
    circle = Circle({
      medium: vm(),
      wards: [max_turns(10)],
    });

    const utterance = makeVmToolCall("const result = await Promise.resolve(42); console.log(result)");
    const result = await circle.execute(utterance, {});

    expect(result.messages[0].content).toContain("42");
  });

  test("gate injection — gates are callable as async functions", async () => {
    const echoGate = gate(
      "Echo the input",
      async ({ text }: { text: string }) => text.toUpperCase(),
      {
        name: "echo",
        schema: {
          type: "object",
          properties: { text: { type: "string" } },
          required: ["text"],
          additionalProperties: false,
        },
        docs: { sandbox_name: "echo", section: "HOST FUNCTIONS" },
      },
    );

    circle = Circle({
      medium: vm(),
      gates: [echoGate],
      wards: [max_turns(10)],
    });

    const utterance = makeVmToolCall('const result = await echo("hello"); console.log(result)');
    const result = await circle.execute(utterance, {});

    expect(result.messages[0].content).toContain("HELLO");
  });

  test("gate results are serialized strings — use JSON.parse for objects", async () => {
    const dataGate = gate(
      "Return an object",
      async () => ({ items: [1, 2, 3], name: "test" }),
      {
        name: "get_data",
        schema: {
          type: "object",
          properties: {},
          additionalProperties: false,
        },
        docs: { sandbox_name: "get_data", section: "HOST FUNCTIONS" },
      },
    );

    circle = Circle({
      medium: vm(),
      gates: [dataGate],
      wards: [max_turns(10)],
    });

    // Gates return serialized strings — entity must JSON.parse for structured data
    const utterance = makeVmToolCall("const raw = await get_data(); const data = JSON.parse(raw); console.log(data.items.length + '-' + data.name)");
    const result = await circle.execute(utterance, {});

    expect(result.messages[0].content).toContain("3-test");
  });

  test("execute handles errors gracefully", async () => {
    circle = Circle({
      medium: vm(),
      wards: [max_turns(10)],
    });

    const utterance = makeVmToolCall("throw new Error('boom')");
    const result = await circle.execute(utterance, {});

    expect(result.done).toBeUndefined();
    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].is_error).toBe(true);
    expect(result.messages[0].content).toContain("boom");
  });

  test("dispose cleans up the context", async () => {
    circle = Circle({
      medium: vm({ state: { context: "test" } }),
      wards: [max_turns(10)],
    });

    await circle.execute(makeVmToolCall("1+1"), {});
    await circle.dispose!();

    try {
      await circle.execute(makeVmToolCall("1+1"), {});
      expect(true).toBe(false);
    } catch (e: any) {
      expect(e.message).toContain("not initialized");
    }

    circle = null;
  });

  test("emits events during execution", async () => {
    circle = Circle({
      medium: vm({ state: { context: "data" } }),
      gates: [done_for_medium()],
      wards: [max_turns(10)],
    });

    const events: any[] = [];
    const utterance = makeVmToolCall('await submit_answer("done")');
    await circle.execute(utterance, {
      on_event: (e) => events.push(e),
    });

    const eventTypes = events.map((e) => e.constructor.name);
    expect(eventTypes).toContain("StepStartEvent");
    expect(eventTypes).toContain("ToolCallEvent");
    expect(eventTypes).toContain("ToolResultEvent");
    expect(eventTypes).toContain("FinalResponseEvent");
  });

  test("capabilityDocs describes vm physics", () => {
    const medium = vm({ state: { data: [1, 2, 3] } });
    const docs = medium.capabilityDocs!();

    expect(docs).toContain("node:vm");
    expect(docs).toContain("ASYNC SUPPORTED");
    expect(docs).toContain("GATE RESULTS");
    expect(docs).toContain("INITIAL STATE");
    expect(docs).toContain("data");
  });
});
