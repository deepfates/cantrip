import { describe, expect, test } from "bun:test";

import { cantrip } from "../../src/cantrip/cantrip";
import { TaskComplete } from "../../src/entity/recording";
import { gate } from "../../src/circle/gate/decorator";
import { Circle } from "../../src/circle/circle";
import type { BoundGate } from "../../src/circle/gate/gate";
import { Loom, MemoryStorage } from "../../src/loom";

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

// ── ENTITY-1: entity only created by casting cantrip ───────────────

describe("ENTITY-1: entity only created by casting cantrip", () => {
  test("ENTITY-1: cantrip.cast() produces a result (entity ran)", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "created" }),
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

    const result = await spell.cast("create entity");
    expect(result).toBe("created");
  });

  test("ENTITY-1: cantrip.invoke() produces an entity whose turn() runs the agent", async () => {
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "invoked" }),
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

    const entity = spell.invoke();
    // Actually call turn() and verify it produces a result
    const result = await entity.cast("test invoke");
    expect(result).toBe("invoked");
  });
});

// ── ENTITY-2: each entity has unique ID ────────────────────────────

describe("ENTITY-2: each entity has unique ID", () => {
  test("ENTITY-2: two invocations produce independent entities", async () => {
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

    const entity1 = spell.invoke();
    const entity2 = spell.invoke();

    await entity1.cast("entity1 msg");
    await entity2.cast("entity2 msg");

    // entity2's call should NOT contain entity1's message
    const entity2Messages = messagesPerCall[1];
    const hasEntity1 = entity2Messages.some(
      (m: any) => typeof m.content === "string" && m.content.includes("entity1 msg"),
    );
    expect(hasEntity1).toBe(false);
  });
});

// ── ENTITY-3: state grows monotonically within a thread ─────────────

describe("ENTITY-3: state grows monotonically within a thread", () => {
  test("ENTITY-3: messages array only grows across turns", async () => {
    let callCount = 0;

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
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
                  arguments: JSON.stringify({ text: "step1" }),
                },
              },
            ],
          };
        }
        if (callCount === 2) {
          return {
            content: null,
            tool_calls: [
              {
                id: "call_2",
                type: "function",
                function: {
                  name: "echo",
                  arguments: JSON.stringify({ text: "step2" }),
                },
              },
            ],
          };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "call_3",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "finished" }),
              },
            },
          ],
        };
      },
    };

    const echoGate = gate("Echo text back", async ({ text }: { text: string }) => text, {
      name: "echo",
      schema: {
        type: "object",
        properties: { text: { type: "string" } },
        required: ["text"],
        additionalProperties: false,
      },
    });

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle([doneGate, echoGate]),
    });

    const entity = spell.invoke();
    await entity.cast("grow test");

    const history = entity.history;
    // History must contain: system, user, assistant+tool (turn1), assistant+tool (turn2), assistant+tool (turn3 done)
    // Each turn adds messages — the array never shrinks
    expect(history.length).toBeGreaterThanOrEqual(5);

    // Verify monotonic growth: check that roles appear in a valid growing sequence
    // (system, user, then alternating assistant/tool messages)
    expect(history[0].role).toBe("system");
    expect(history[1].role).toBe("user");
    // Remaining messages should alternate between assistant and tool roles
    for (let i = 2; i < history.length; i++) {
      expect(["assistant", "tool"]).toContain(history[i].role);
    }
  });

  test("ENTITY-3: second cast() preserves prior state and grows further", async () => {
    let callCount = 0;

    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        callCount++;
        return {
          content: null,
          tool_calls: [
            {
              id: `call_${callCount}`,
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: `result${callCount}` }),
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

    const entity = spell.invoke();
    await entity.cast("first intent");
    const historyAfterFirst = entity.history.length;

    await entity.cast("second intent");
    const historyAfterSecond = entity.history.length;

    // History must grow monotonically — second cast adds to existing state
    expect(historyAfterSecond).toBeGreaterThan(historyAfterFirst);
  });
});

// ── ENTITY-4: entity thread persists after termination ─────────────

describe("ENTITY-4: entity thread persists after termination", () => {
  test("ENTITY-4: agent history contains structured turns after query completes", async () => {
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

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });

    const entity = spell.invoke();
    await entity.cast("persist test");

    const history = entity.history;
    // History should contain at least: system, user, assistant messages
    expect(history.length).toBeGreaterThanOrEqual(3);
    // First message is system prompt
    expect(history[0].role).toBe("system");
    expect((history[0] as any).content).toBe("test");
    // Second message is the user intent
    expect(history[1].role).toBe("user");
    expect((history[1] as any).content).toBe("persist test");
    // Third message is assistant response with tool calls
    expect(history[2].role).toBe("assistant");
  });
});

// ── ENTITY-5: invoke creates entity, ENTITY-6: turn runs a step ────

describe("ENTITY-5/6: invoke and turn API", () => {
  test("ENTITY-5: invoke() creates an entity without running a step", () => {
    const crystal = makeLlm([]);
    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });
    const entity = spell.invoke();
    // Entity exists but no turn has run yet
    expect(entity).toBeDefined();
    expect(entity.history.length).toBe(0);
  });

  test("ENTITY-6: turn() runs one agent loop step and returns result", async () => {
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
      call: { system_prompt: "test" },
      circle: makeCircle(),
    });

    const entity = spell.invoke();
    const result = await entity.cast("do something");
    expect(result).toBe("hello from turn");
  });
});
