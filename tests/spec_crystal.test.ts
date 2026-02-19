import { describe, expect, test } from "bun:test";

import { cantrip } from "../src/cantrip/cantrip";
import { TaskComplete } from "../src/entity/errors";
import { tool } from "../src/circle/gate/decorator";
import type { Circle } from "../src/circle/circle";

// ── Shared helpers ─────────────────────────────────────────────────

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const doneGate = tool("Signal completion", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const echoGate = tool("Echo text back", async ({ text }: { text: string }) => text, {
  name: "echo",
  schema: {
    type: "object",
    properties: { text: { type: "string" } },
    required: ["text"],
    additionalProperties: false,
  },
});

function makeCircle(gates = [doneGate], wards = [{ max_turns: 10, require_done_tool: true }]): Circle {
  return { gates, wards };
}

// ── CRYSTAL-1: crystal is stateless between invocations ────────────

describe("CRYSTAL-1: crystal is stateless between invocations", () => {
  test("CRYSTAL-1: each invocation receives full context, not incremental", async () => {
    const messagesPerCall: any[][] = [];
    let callCount = 0;

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        messagesPerCall.push([...messages]);
        callCount++;
        if (callCount === 1) {
          return {
            content: null,
            tool_calls: [
              {
                id: "call_1",
                type: "function",
                function: {
                  name: "echo",
                  arguments: JSON.stringify({ text: "call 1" }),
                },
              },
            ],
          };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "call_2",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "done" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle([doneGate, echoGate]),
    });

    await spell.cast("test statelessness");

    expect(messagesPerCall.length).toBe(2);
    // Second invocation has ALL messages from the start, not just the new ones
    expect(messagesPerCall[1].length).toBeGreaterThan(messagesPerCall[0].length);
    // First message of both calls is the system prompt
    expect(messagesPerCall[0][0].role).toBe("system");
    expect(messagesPerCall[1][0].role).toBe("system");
  });
});

// ── CRYSTAL-2: crystal accepts many messages ───────────────────────

describe("CRYSTAL-2: crystal accepts many messages", () => {
  test("CRYSTAL-2: crystal handles 6 turns of accumulated context", async () => {
    let callCount = 0;
    const messagesPerCall: any[][] = [];

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        messagesPerCall.push([...messages]);
        callCount++;
        if (callCount <= 5) {
          return {
            content: null,
            tool_calls: [
              {
                id: `call_${callCount}`,
                type: "function",
                function: {
                  name: "echo",
                  arguments: JSON.stringify({ text: `${callCount}` }),
                },
              },
            ],
          };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "call_done",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "ok" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle([doneGate, echoGate]),
    });

    const result = await spell.cast("test many messages");
    expect(result).toBe("ok");
    expect(callCount).toBe(6);

    // Last invocation should have many messages
    const lastCall = messagesPerCall[messagesPerCall.length - 1];
    expect(lastCall.length).toBeGreaterThan(10);
  });
});

// ── CRYSTAL-3: crystal must return content or tool_calls ───────────

describe("CRYSTAL-3: crystal must return content or tool_calls", () => {
  test("CRYSTAL-3: empty response with require_done=false returns empty string result", async () => {
    // When crystal returns neither content nor tool_calls, and done is not required,
    // the agent loop should terminate with an empty/summary string result
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        return { content: null, tool_calls: null };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(
        [doneGate],
        [{ max_turns: 1, require_done_tool: false }],
      ),
    });

    const result = await spell.cast("test empty response");
    // With require_done_tool=false and no content/tool_calls, the agent
    // terminates and returns an empty or summary string
    expect(typeof result).toBe("string");
    expect(result).toBe("");
  });
});

// ── CRYSTAL-4: tool calls must have unique IDs ─────────────────────
// TODO: untestable until the framework validates and rejects duplicate
// tool call IDs. Currently duplicate IDs are silently accepted and both
// calls are executed, which violates CRYSTAL-4 but isn't enforced.

// ── CRYSTAL-5: required tool_choice forces gate use ────────────────

describe("CRYSTAL-5: required tool_choice forces gate use", () => {
  test("CRYSTAL-5: tool_choice=required is stored in resolved call and passed to entity", async () => {
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        return {
          content: null,
          tool_calls: [
            {
              id: "call_1",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "ok" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: {
        system_prompt: "test",
        hyperparameters: { tool_choice: "required" },
      },
      circle: makeCircle(
        [doneGate],
        [{ max_turns: 10, require_done_tool: true }],
      ),
    });

    // Verify the resolved call stores tool_choice=required
    expect(spell.call.hyperparameters.tool_choice).toBe("required");

    const result = await spell.cast("test required");
    expect(result).toBe("ok");
  });
});

// ── CRYSTAL-6: provider responses normalized ───────────────────────

describe("CRYSTAL-6: provider responses normalized to crystal contract", () => {
  test("CRYSTAL-6: crystal response with content returns content as result and tracks usage", async () => {
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        return {
          content: "hello",
          tool_calls: [],
          usage: { prompt_tokens: 10, completion_tokens: 5 },
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(
        [doneGate],
        [{ max_turns: 10, require_done_tool: false }],
      ),
    });

    // Use invoke() so we can inspect the agent for usage tracking
    const entity = spell.invoke();
    const result = await entity.turn("test normalization");

    // Content is normalized: returned as-is as the result string
    expect(result).toBe("hello");

    // Usage is captured from the crystal response
    const usage = await entity.get_usage();
    expect(usage.total_prompt_tokens).toBe(10);
    expect(usage.total_completion_tokens).toBe(5);
  });
});
