import { describe, expect, test, afterEach } from "bun:test";

import { Circle } from "../src/circle/circle";
import type { Circle as CircleType } from "../src/circle/circle";
import { max_turns, require_done } from "../src/circle/ward";
import { js, getJsMediumSandbox } from "../src/circle/medium/js";
import type { AssistantMessage } from "../src/crystal/messages";

// ── Helpers ──────────────────────────────────────────────────────────

function makeJsToolCall(code: string, id = "call_1"): AssistantMessage {
  return {
    role: "assistant",
    content: null,
    tool_calls: [
      {
        id,
        type: "function",
        function: {
          name: "js",
          arguments: JSON.stringify({ code }),
        },
      },
    ],
  };
}

// ── Tests ────────────────────────────────────────────────────────────

describe("Circle with JS medium", () => {
  let circle: CircleType | null = null;

  afterEach(async () => {
    if (circle?.dispose) await circle.dispose();
    circle = null;
  });

  test("constructs without done gate when medium present", () => {
    circle = Circle({
      medium: js(),
      wards: [max_turns(10)],
    });
    expect(circle.hasMedium).toBe(true);
    expect(circle.gates).toHaveLength(0);
  });

  test("constructs with gates when medium present", () => {
    circle = Circle({
      medium: js({ state: { x: 42 } }),
      gates: [],
      wards: [max_turns(10)],
    });
    expect(circle.hasMedium).toBe(true);
  });

  test("crystalView returns js tool with required tool_choice", () => {
    circle = Circle({
      medium: js(),
      wards: [max_turns(10)],
    });
    const view = circle.crystalView();
    expect(view.tool_definitions).toHaveLength(1);
    expect(view.tool_definitions[0].function.name).toBe("js");
    expect(view.tool_choice).toEqual({ type: "tool", name: "js" });
  });

  test("execute runs code in sandbox and returns metadata", async () => {
    circle = Circle({
      medium: js({ state: { context: { answer: 42 } } }),
      wards: [max_turns(10)],
    });

    const utterance = makeJsToolCall("JSON.stringify(context)");
    const result = await circle.execute(utterance, {});

    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].role).toBe("tool");
    expect(result.done).toBeUndefined();
    // Result should be formatted as metadata (not raw JSON)
    expect(result.messages[0].content).toContain("[Result:");
  });

  test("execute handles submit_answer termination", async () => {
    circle = Circle({
      medium: js({ state: { context: "hello" } }),
      wards: [max_turns(10)],
    });

    const utterance = makeJsToolCall('submit_answer("the answer is 42")');
    const result = await circle.execute(utterance, {});

    expect(result.done).toBe("the answer is 42");
    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].content).toContain("Task completed");
  });

  test("state persists across execute calls", async () => {
    circle = Circle({
      medium: js({ state: { context: [1, 2, 3] } }),
      wards: [max_turns(10)],
    });

    // First call: set a variable
    const r1 = await circle.execute(makeJsToolCall("var total = context.reduce(function(a,b){return a+b}, 0)"), {});
    expect(r1.done).toBeUndefined();

    // Second call: use the variable and submit
    const r2 = await circle.execute(makeJsToolCall("submit_answer(String(total))"), {});
    expect(r2.done).toBe("6");
  });

  test("execute handles errors gracefully", async () => {
    circle = Circle({
      medium: js(),
      wards: [max_turns(10)],
    });

    const utterance = makeJsToolCall("throw new Error('boom')");
    const result = await circle.execute(utterance, {});

    expect(result.done).toBeUndefined();
    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].is_error).toBe(true);
    expect(result.messages[0].content).toContain("boom");
  });

  test("dispose cleans up the sandbox", async () => {
    circle = Circle({
      medium: js({ state: { context: "test" } }),
      wards: [max_turns(10)],
    });

    // Initialize by executing
    await circle.execute(makeJsToolCall("1+1"), {});

    // Dispose
    await circle.dispose!();

    // Executing after dispose should fail
    try {
      await circle.execute(makeJsToolCall("1+1"), {});
      expect(true).toBe(false); // should not reach here
    } catch (e: any) {
      // After dispose, sandbox is null and initialized is false
      expect(e.message).toContain("not initialized");
    }

    circle = null; // prevent double dispose in afterEach
  });

  test("getJsMediumSandbox returns sandbox after init", async () => {
    const medium = js({ state: { context: "test" } });
    circle = Circle({
      medium,
      wards: [max_turns(10)],
    });

    // Before init, sandbox may be null
    // After execute (which triggers lazy init), sandbox should exist
    await circle.execute(makeJsToolCall("1+1"), {});
    const sandbox = getJsMediumSandbox(medium);
    expect(sandbox).not.toBeNull();
  });

  test("emits events during execution", async () => {
    circle = Circle({
      medium: js({ state: { context: "data" } }),
      wards: [max_turns(10)],
    });

    const events: any[] = [];
    const utterance = makeJsToolCall('submit_answer("done")');
    await circle.execute(utterance, {
      on_event: (e) => events.push(e),
    });

    const eventTypes = events.map((e) => e.constructor.name);
    expect(eventTypes).toContain("StepStartEvent");
    expect(eventTypes).toContain("ToolCallEvent");
    expect(eventTypes).toContain("ToolResultEvent");
    expect(eventTypes).toContain("FinalResponseEvent");
  });
});
