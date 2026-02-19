import { describe, expect, test } from "bun:test";

import { cantrip } from "../src/cantrip/cantrip";
import { TaskComplete } from "../src/entity/service";
import { gate } from "../src/circle/gate/decorator";
import { Circle } from "../src/circle/circle";
import type { GateResult } from "../src/circle/gate/gate";

// ── Shared helpers ─────────────────────────────────────────────────

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const doneGate = gate("Signal completion", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const ward = { max_turns: 10, require_done_tool: true };

function makeCircle(gates: GateResult[] = [doneGate], wards = [ward]) {
  return Circle({ gates, wards });
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

// ── CANTRIP-1: cantrip requires crystal, call, and circle ──────────

describe("CANTRIP-1: cantrip requires crystal, call, and circle", () => {
  test("CANTRIP-1: throws when crystal is missing", () => {
    expect(() =>
      cantrip({
        crystal: undefined as any,
        call: { system_prompt: "test" },
        circle: makeCircle(),
      }),
    ).toThrow(/crystal/i);
  });

  test("CANTRIP-1: throws when call is missing", () => {
    const crystal = makeLlm([]);
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: undefined as any,
        circle: makeCircle(),
      }),
    ).toThrow(/call/i);
  });

  test("CANTRIP-1: throws when circle is missing", () => {
    const crystal = makeLlm([]);
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: { system_prompt: "test" },
        circle: undefined as any,
      }),
    ).toThrow(/circle/i);
  });

  test("CANTRIP-1: succeeds with all three present", () => {
    const crystal = makeLlm([]);
    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });
    expect(spell).toBeDefined();
    expect(typeof spell.cast).toBe("function");
  });
});

// ── CANTRIP-2: cantrip is reusable across intents ──────────────────

describe("CANTRIP-2: cantrip is reusable across intents", () => {
  test("CANTRIP-2: two casts produce independent results", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "first" }),
            },
          },
        ],
      }),
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_2",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "second" }),
            },
          },
        ],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "You are helpful" },
      circle: makeCircle(),
    });

    const result1 = await spell.cast("first task");
    const result2 = await spell.cast("second task");

    expect(result1).toBe("first");
    expect(result2).toBe("second");
  });

  test("CANTRIP-2: second cast does not see first cast's messages", async () => {
    const messagesPerCall: any[][] = [];
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        messagesPerCall.push([...messages]);
        return {
          content: null,
          tool_calls: [
            {
              id: `call_${messagesPerCall.length}`,
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: `r${messagesPerCall.length}` }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });

    await spell.cast("first intent");
    await spell.cast("second intent");

    // Second call should not contain "first intent"
    const secondCallMessages = messagesPerCall[1];
    const hasFirst = secondCallMessages.some(
      (m: any) => typeof m.content === "string" && m.content.includes("first intent"),
    );
    expect(hasFirst).toBe(false);
  });

  test("CANTRIP-2: null system_prompt is valid (minimal cantrip)", async () => {
    const messagesPerCall: any[][] = [];
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        messagesPerCall.push([...messages]);
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
      call: { system_prompt: null },
      circle: makeCircle(),
    });

    const result = await spell.cast("minimal test");
    expect(result).toBe("ok");

    // First message should be user (no system message)
    const firstMessage = messagesPerCall[0][0];
    expect(firstMessage.role).toBe("user");
    expect(firstMessage.content).toBe("minimal test");
  });
});

// ── CANTRIP-3: validates circle has done gate and truncation ward ──

describe("CANTRIP-3: cantrip validates circle constraints", () => {
  test("CANTRIP-3: throws if circle has no done gate", () => {
    const crystal = makeLlm([]);
    const notDone = gate("Not done", async () => "ok", {
      name: "other",
      schema: { type: "object", properties: {}, additionalProperties: false },
    });
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: { system_prompt: "test" },
        circle: makeCircle([notDone]),
      }),
    ).toThrow(/done/i);
  });

  test("CANTRIP-3: throws if circle has no ward", () => {
    const crystal = makeLlm([]);
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: { system_prompt: "test" },
        circle: makeCircle([doneGate], []),
      }),
    ).toThrow(/ward/i);
  });
});
