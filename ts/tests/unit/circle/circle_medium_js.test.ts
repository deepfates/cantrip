import { describe, expect, test, afterEach } from "bun:test";

import { js, getJsMediumSandbox } from "../../../src/circle/medium/js";
import { Circle } from "../../../src/circle/circle";
import { max_turns } from "../../../src/circle/ward";
import type { BoundGate } from "../../../src/circle/gate/gate";
import type { AssistantMessage } from "../../../src/crystal/messages";

// ── Helpers ──────────────────────────────────────────────────────────

function makeJsToolCall(code: string, id = "call_1"): AssistantMessage {
  return {
    role: "assistant",
    content: null,
    tool_calls: [
      {
        id,
        type: "function",
        function: { name: "js", arguments: JSON.stringify({ code }) },
      },
    ],
  };
}

/** Create a simple gate that records the args it was called with. */
function mockGate(overrides: Partial<BoundGate> & { name: string }): BoundGate {
  return {
    definition: {
      name: overrides.name,
      description: `Mock gate: ${overrides.name}`,
      parameters: {
        type: "object",
        properties: {
          intent: { type: "string", description: "The intent" },
          context: { type: "string", description: "Optional context" },
        },
        required: ["intent"],
        additionalProperties: false,
      },
    },
    ephemeral: false,
    execute: async (args) => JSON.stringify(args),
    ...overrides,
  };
}

// ── Tests ────────────────────────────────────────────────────────────

describe("JS medium gate presentation", () => {
  let circle: ReturnType<typeof Circle> | null = null;

  afterEach(async () => {
    if (circle?.dispose) await circle.dispose();
    circle = null;
  });

  test("gate with docs.sandbox_name registers under that name", async () => {
    const gate = mockGate({
      name: "call_entity",
      docs: {
        sandbox_name: "call_entity",
        description: "Delegate to child entity",
      },
    });

    circle = Circle({
      medium: js(),
      gates: [gate],
      wards: [max_turns(10)],
    });

    // Execute code that calls the sandbox_name
    const result = await circle.execute(
      makeJsToolCall('call_entity("hello")'),
      {},
    );

    expect(result.done).toBeUndefined();
    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].is_error).toBeFalsy();
    // The gate should have received { intent: "hello" }
    expect(result.messages[0].content).toContain("intent");
    expect(result.messages[0].content).toContain("hello");
  });

  test("gate without docs registers under gate.name", async () => {
    const gate = mockGate({ name: "my_gate" });

    circle = Circle({
      medium: js(),
      gates: [gate],
      wards: [max_turns(10)],
    });

    // Execute code calling by gate.name
    const result = await circle.execute(
      makeJsToolCall('my_gate("test")'),
      {},
    );

    expect(result.done).toBeUndefined();
    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].is_error).toBeFalsy();
    expect(result.messages[0].content).toContain("test");
  });

  test("positional args mapped correctly to gate parameters", async () => {
    let capturedArgs: Record<string, unknown> | null = null;

    const gate = mockGate({
      name: "call_entity",
      docs: { sandbox_name: "call_entity" },
      execute: async (args) => {
        capturedArgs = args;
        return JSON.stringify(args);
      },
    });

    circle = Circle({
      medium: js(),
      gates: [gate],
      wards: [max_turns(10)],
    });

    // Call with two positional args — should map to "intent" and "context"
    const result = await circle.execute(
      makeJsToolCall('call_entity("summarize this", "some context data")'),
      {},
    );

    expect(result.messages[0].is_error).toBeFalsy();
    expect(capturedArgs).not.toBeNull();
    expect(capturedArgs!.intent).toBe("summarize this");
    expect(capturedArgs!.context).toBe("some context data");
  });

  test("single object arg passes through directly", async () => {
    let capturedArgs: Record<string, unknown> | null = null;

    const gate = mockGate({
      name: "call_entity",
      docs: { sandbox_name: "call_entity" },
      execute: async (args) => {
        capturedArgs = args;
        return JSON.stringify(args);
      },
    });

    circle = Circle({
      medium: js(),
      gates: [gate],
      wards: [max_turns(10)],
    });

    // Call with a single object arg — should pass through directly
    const result = await circle.execute(
      makeJsToolCall('call_entity({ intent: "hello", context: "world" })'),
      {},
    );

    expect(result.messages[0].is_error).toBeFalsy();
    expect(capturedArgs).not.toBeNull();
    expect(capturedArgs!.intent).toBe("hello");
    expect(capturedArgs!.context).toBe("world");
  });
});
