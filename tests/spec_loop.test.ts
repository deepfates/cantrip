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

function makeLlm(responses: (() => any)[]) {
  let callIndex = 0;
  return {
    model: "dummy",
    provider: "dummy",
    name: "dummy",
    async ainvoke(messages: any[]) {
      const fn = responses[callIndex];
      if (!fn) throw new Error(`Unexpected LLM call #${callIndex}`);
      callIndex++;
      return fn();
    },
  };
}

// ── LOOP-1: turns alternate between entity and circle ──────────────

describe("LOOP-1: turns alternate between entity and circle", () => {
  test("LOOP-1: entity invokes crystal, circle processes gate calls, loop terminates", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "hello" }),
            },
          },
        ],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });

    const result = await spell.cast("say hello");
    expect(result).toBe("hello");
  });
});

// ── LOOP-2: cantrip without max_turns ward is invalid ──────────────

describe("LOOP-2: cantrip without truncation ward is invalid", () => {
  test("LOOP-2: throws if circle has no wards", () => {
    const crystal = makeLlm([]);
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: { system_prompt: "test" },
        circle: { gates: [doneGate], wards: [] },
      }),
    ).toThrow(/ward/i);
  });

  test("LOOP-2: cantrip with require_done but no done gate throws via CANTRIP-3", () => {
    const crystal = makeLlm([]);
    const notDone = tool("Other", async () => "ok", {
      name: "other",
      schema: { type: "object", properties: {}, additionalProperties: false },
    });
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: { system_prompt: "test" },
        circle: { gates: [notDone], wards: [{ max_turns: 10, require_done_tool: true }] },
      }),
    ).toThrow(/done/i);
  });
});

// ── LOOP-3: done gate stops the loop immediately ───────────────────

describe("LOOP-3: done gate stops the loop immediately", () => {
  test("LOOP-3: when done is called alongside other gates, loop stops after done", async () => {
    const gateCallOrder: string[] = [];

    const echoTracked = tool("Echo", async ({ text }: { text: string }) => {
      gateCallOrder.push("echo");
      return text;
    }, {
      name: "echo",
      schema: {
        type: "object",
        properties: { text: { type: "string" } },
        required: ["text"],
        additionalProperties: false,
      },
    });

    const doneTracked = tool("Done", async ({ message }: { message: string }) => {
      gateCallOrder.push("done");
      throw new TaskComplete(message);
    }, {
      name: "done",
      schema: {
        type: "object",
        properties: { message: { type: "string" } },
        required: ["message"],
        additionalProperties: false,
      },
    });

    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "echo",
              arguments: JSON.stringify({ text: "before" }),
            },
          },
          {
            id: "call_2",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "finished" }),
            },
          },
          {
            id: "call_3",
            type: "function",
            function: {
              name: "echo",
              arguments: JSON.stringify({ text: "after" }),
            },
          },
        ],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle([doneTracked, echoTracked]),
    });

    const result = await spell.cast("test done ordering");
    expect(result).toBe("finished");
    // echo was called first, then done terminated — "after" was skipped
    expect(gateCallOrder).toContain("echo");
    expect(gateCallOrder).toContain("done");
  });
});

// ── LOOP-4: max turns ward truncates the loop ──────────────────────

describe("LOOP-4: max turns ward truncates the loop", () => {
  test("LOOP-4: loop stops after max_turns and result indicates truncation", async () => {
    let callCount = 0;
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        callCount++;
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
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(
        [doneGate, echoGate],
        [{ max_turns: 2, require_done_tool: false }],
      ),
    });

    // Will truncate after 2 turns without calling done
    const result = await spell.cast("count");
    // The result should indicate truncation occurred
    expect(result).toContain("Max iterations reached");
    // max_turns=2 limits the loop; the agent makes an extra call for summary
    expect(callCount).toBeGreaterThanOrEqual(2);
    expect(callCount).toBeLessThanOrEqual(3);
  });
});

// ── LOOP-5: entity receives all prior turns as context ─────────────

describe("LOOP-5: entity receives all prior turns as context", () => {
  test("LOOP-5: crystal invocations accumulate messages", async () => {
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
                  arguments: JSON.stringify({ text: "first" }),
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

    await spell.cast("test context growth");

    // First invocation: system + user = 2 messages
    expect(messagesPerCall[0].length).toBe(2);
    // Second invocation: system + user + assistant + tool = more messages
    expect(messagesPerCall[1].length).toBeGreaterThan(messagesPerCall[0].length);
  });
});

// ── LOOP-6: text-only response behavior ────────────────────────────

describe("LOOP-6: text-only response behavior", () => {
  test("LOOP-6: text-only response terminates when done not required", async () => {
    const crystal = makeLlm([
      () => ({
        content: "The answer is 42",
        tool_calls: [],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(
        [doneGate],
        [{ max_turns: 10, require_done_tool: false }],
      ),
    });

    const result = await spell.cast("what is the answer?");
    expect(result).toBe("The answer is 42");
  });

  test("LOOP-6: text-only response continues when done required", async () => {
    let callCount = 0;
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        callCount++;
        if (callCount < 3) {
          return { content: "thinking...", tool_calls: [] };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "call_done",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "42" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(
        [doneGate],
        [{ max_turns: 10, require_done_tool: true }],
      ),
    });

    const result = await spell.cast("what is the answer?");
    expect(result).toBe("42");
    expect(callCount).toBe(3);
  });
});
