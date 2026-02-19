import { describe, expect, test } from "bun:test";

import { cantrip } from "../src/cantrip/cantrip";
import { TaskComplete } from "../src/entity/recording";
import { gate } from "../src/circle/gate/decorator";
import { Circle } from "../src/circle/circle";
import type { Ward } from "../src/circle/ward";
import type { BoundGate } from "../src/circle/gate/gate";

// ── Helpers ──────────────────────────────────────────────────────────

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const doneGate = gate("Done", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const ward: Ward = { max_turns: 10, require_done_tool: true };

function makeCircle(gates: BoundGate[] = [doneGate], wards = [ward]) {
  return Circle({ gates, wards });
}

function makeLlm(responses: (() => any)[]) {
  let callIndex = 0;
  return {
    model: "dummy",
    provider: "dummy",
    name: "dummy",
    async query(messages: any[]) {
      const fn = responses[callIndex];
      if (!fn) throw new Error(`Unexpected LLM call #${callIndex}`);
      callIndex++;
      return fn();
    },
  };
}

// ── Tests ────────────────────────────────────────────────────────────

describe("cantrip", () => {
  test("cantrip() returns an object with .cast()", () => {
    const crystal = makeLlm([]);
    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });
    expect(spell).toBeDefined();
    expect(typeof spell.cast).toBe("function");
  });

  test("cantrip() throws if crystal is missing", () => {
    expect(() =>
      cantrip({
        crystal: undefined as any,
        call: { system_prompt: "test" },
        circle: makeCircle(),
      }),
    ).toThrow();
  });

  test("cantrip() throws if call is missing", () => {
    const crystal = makeLlm([]);
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: undefined as any,
        circle: makeCircle(),
      }),
    ).toThrow();
  });

  test("cantrip() throws if circle is missing", () => {
    const crystal = makeLlm([]);
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: { system_prompt: "test" },
        circle: undefined as any,
      }),
    ).toThrow();
  });

  test("CANTRIP-3: throws if circle has no done gate", () => {
    const crystal = makeLlm([]);
    const noDoneGate = gate("Not done", async () => "ok", {
      name: "other",
      schema: { type: "object", properties: {}, additionalProperties: false },
    });
    expect(() =>
      cantrip({
        crystal: crystal as any,
        call: { system_prompt: "test" },
        circle: makeCircle([noDoneGate]),
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

  test("cast() runs the agent loop and returns the done result", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "finished" }),
            },
          },
        ],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const result = await spell.cast("do something");
    expect(result).toBe("finished");
  });

  test("INTENT-1: cast() throws if intent is not provided", async () => {
    const crystal = makeLlm([]);
    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });

    await expect(spell.cast(undefined as any)).rejects.toThrow(/intent/i);
    await expect(spell.cast("")).rejects.toThrow(/intent/i);
  });

  test("CANTRIP-2: each cast is independent — no shared state", async () => {
    // Track messages passed to LLM to verify independence
    const messagesPerCall: any[][] = [];

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
        messagesPerCall.push([...messages]);
        return {
          content: null,
          tool_calls: [
            {
              id: "call_1",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({
                  message: `result-${messagesPerCall.length}`,
                }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const result1 = await spell.cast("first intent");
    const result2 = await spell.cast("second intent");

    expect(result1).toBe("result-1");
    expect(result2).toBe("result-2");

    // The second cast should NOT contain "first intent" in its messages
    const secondCallMessages = messagesPerCall[1];
    const userMessages = secondCallMessages.filter(
      (m: any) => m.role === "user",
    );
    expect(userMessages.length).toBe(1);
    expect(userMessages[0].content).toBe("second intent");
    // Verify no "first intent" leaked into second call
    const hasFirstIntent = secondCallMessages.some(
      (m: any) =>
        typeof m.content === "string" && m.content.includes("first intent"),
    );
    expect(hasFirstIntent).toBe(false);
  });

  // ── invoke() and cast() ──────────────────────────────────────────

  test("invoke() returns an entity with .cast()", () => {
    const crystal = makeLlm([]);
    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });
    const entity = spell.invoke();
    expect(entity).toBeDefined();
    expect(typeof entity.cast).toBe("function");
  });

  test("cast() runs the agent loop and returns the done result", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "hello from turn" }),
            },
          },
        ],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const entity = spell.invoke();
    const result = await entity.cast("do something");
    expect(result).toBe("hello from turn");
  });

  test("two turns accumulate state (second turn sees first turn context)", async () => {
    const messagesPerCall: any[][] = [];

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
        messagesPerCall.push([...messages]);
        return {
          content: null,
          tool_calls: [
            {
              id: `call_${messagesPerCall.length}`,
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({
                  message: `result-${messagesPerCall.length}`,
                }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const entity = spell.invoke();
    await entity.cast("first message");
    await entity.cast("second message");

    // The second LLM call should see the first turn's context
    const secondCallMessages = messagesPerCall[1];
    const userMessages = secondCallMessages.filter(
      (m: any) => m.role === "user",
    );
    // Should have both "first message" and "second message"
    expect(userMessages.length).toBe(2);
    expect(userMessages[0].content).toBe("first message");
    expect(userMessages[1].content).toBe("second message");
  });

  test("two invoke() calls on same cantrip → independent entities", async () => {
    const messagesPerCall: any[][] = [];

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
        messagesPerCall.push([...messages]);
        return {
          content: null,
          tool_calls: [
            {
              id: `call_${messagesPerCall.length}`,
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({
                  message: `result-${messagesPerCall.length}`,
                }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const entity1 = spell.invoke();
    const entity2 = spell.invoke();

    await entity1.cast("entity1 message");
    await entity2.cast("entity2 message");

    // entity2's LLM call should NOT contain "entity1 message"
    const entity2Messages = messagesPerCall[1];
    const hasEntity1Content = entity2Messages.some(
      (m: any) =>
        typeof m.content === "string" && m.content.includes("entity1 message"),
    );
    expect(hasEntity1Content).toBe(false);

    // entity2 should only have its own user message
    const entity2UserMessages = entity2Messages.filter(
      (m: any) => m.role === "user",
    );
    expect(entity2UserMessages.length).toBe(1);
    expect(entity2UserMessages[0].content).toBe("entity2 message");
  });

  test("entity exposes spec parts (crystal, call, circle)", () => {
    const crystal = makeLlm([]);
    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });
    const entity = spell.invoke();
    expect(entity.crystal).toBeDefined();
    expect(entity.call).toBeDefined();
    expect(entity.circle).toBeDefined();
  });

  test("call with simple system_prompt derives gate_definitions from circle", async () => {
    const crystal = makeLlm([
      () => ({
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
      }),
    ]);

    // Providing call as just { system_prompt: "..." } — no gate_definitions or hyperparameters
    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "Simple prompt" },
      circle: makeCircle(),
    });

    const result = await spell.cast("test");
    expect(result).toBe("ok");
  });
});
