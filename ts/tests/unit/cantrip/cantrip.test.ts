import { describe, expect, test } from "bun:test";

import { cantrip } from "../../../src/cantrip/cantrip";
import { TaskComplete } from "../../../src/entity/recording";
import { gate } from "../../../src/circle/gate/decorator";
import { Circle } from "../../../src/circle/circle";
import type { Ward } from "../../../src/circle/ward";
import type { BoundGate } from "../../../src/circle/gate/gate";

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
    const llm = makeLlm([]);
    const spell = cantrip({
      llm: llm as any,
      identity: { system_prompt: "test" },
      circle: makeCircle(),
    });
    expect(spell).toBeDefined();
    expect(typeof spell.cast).toBe("function");
  });

  test("cantrip() throws if llm is missing", () => {
    expect(() =>
      cantrip({
        llm: undefined as any,
        identity: { system_prompt: "test" },
        circle: makeCircle(),
      }),
    ).toThrow();
  });

  test("cantrip() throws if call is missing", () => {
    const llm = makeLlm([]);
    expect(() =>
      cantrip({
        llm: llm as any,
        identity: undefined as any,
        circle: makeCircle(),
      }),
    ).toThrow();
  });

  test("cantrip() throws if circle is missing", () => {
    const llm = makeLlm([]);
    expect(() =>
      cantrip({
        llm: llm as any,
        identity: { system_prompt: "test" },
        circle: undefined as any,
      }),
    ).toThrow();
  });

  test("CIRCLE-1: circle rejects missing done gate", () => {
    const noDoneGate = gate("Not done", async () => "ok", {
      name: "other",
      schema: { type: "object", properties: {}, additionalProperties: false },
    });
    expect(() => makeCircle([noDoneGate])).toThrow(/done/i);
  });

  test("CIRCLE-2: circle rejects missing termination ward", () => {
    expect(() => makeCircle([doneGate], [])).toThrow(/ward/i);
  });

  test("cast() runs the agent loop and returns the done result", async () => {
    const llm = makeLlm([
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
      llm: llm as any,
      identity: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const result = await spell.cast("do something");
    expect(result).toBe("finished");
  });

  test("INTENT-1: cast() throws if intent is not provided", async () => {
    const llm = makeLlm([]);
    const spell = cantrip({
      llm: llm as any,
      identity: { system_prompt: "test" },
      circle: makeCircle(),
    });

    await expect(spell.cast(undefined as any)).rejects.toThrow(/intent/i);
    await expect(spell.cast("")).rejects.toThrow(/intent/i);
  });

  test("CANTRIP-2: each cast is independent — no shared state", async () => {
    // Track messages passed to LLM to verify independence
    const messagesPerCall: any[][] = [];

    const llm = {
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
      llm: llm as any,
      identity: { system_prompt: "You are a helper." },
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

  // ── summon() and cast() ──────────────────────────────────────────

  test("summon() returns an entity with .cast()", () => {
    const llm = makeLlm([]);
    const spell = cantrip({
      llm: llm as any,
      identity: { system_prompt: "test" },
      circle: makeCircle(),
    });
    const entity = spell.summon();
    expect(entity).toBeDefined();
    expect(typeof entity.cast).toBe("function");
  });

  test("cast() runs the agent loop and returns the done result", async () => {
    const llm = makeLlm([
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
      llm: llm as any,
      identity: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const entity = spell.summon();
    const result = await entity.cast("do something");
    expect(result).toBe("hello from turn");
  });

  test("two turns accumulate state (second turn sees first turn context)", async () => {
    const messagesPerCall: any[][] = [];

    const llm = {
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
      llm: llm as any,
      identity: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const entity = spell.summon();
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

  test("two summon() calls on same cantrip → independent entities", async () => {
    const messagesPerCall: any[][] = [];

    const llm = {
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
      llm: llm as any,
      identity: { system_prompt: "You are a helper." },
      circle: makeCircle(),
    });

    const entity1 = spell.summon();
    const entity2 = spell.summon();

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

  test("cast() awaits async circle dispose (medium cleanup)", async () => {
    // The bug: entity.dispose() was sync, so async circle.dispose() (from mediums)
    // returned a Promise that was never awaited. This test verifies that by the time
    // cast() returns, the medium's async dispose has fully completed.
    let disposeFinished = false;

    const mockMedium = {
      async init() {},
      toolView() {
        return {
          tool_definitions: [{
            name: "js",
            description: "run code",
            parameters: { type: "object", properties: { code: { type: "string" } }, required: ["code"] },
          }],
          tool_choice: { type: "tool" as const, name: "js" },
        };
      },
      async execute() {
        return {
          messages: [{
            role: "tool" as const,
            tool_call_id: "call_1",
            tool_name: "js",
            content: "Task completed: done",
            is_error: false,
          }],
          gate_calls: [],
          done: "done",
        };
      },
      async dispose() {
        await new Promise(resolve => setTimeout(resolve, 10));
        disposeFinished = true;
      },
    };

    const llm = makeLlm([
      () => ({
        content: null,
        tool_calls: [{
          id: "call_1",
          type: "function",
          function: { name: "js", arguments: JSON.stringify({ code: "submit_answer('done')" }) },
        }],
      }),
    ]);

    const circle = Circle({
      medium: mockMedium as any,
      wards: [ward],
    });

    const spell = cantrip({
      llm: llm as any,
      identity: { system_prompt: "test" },
      circle,
    });

    await spell.cast("test intent");
    expect(disposeFinished).toBe(true);
  });

  test("entity exposes spec parts (llm, identity, circle)", () => {
    const llm = makeLlm([]);
    const spell = cantrip({
      llm: llm as any,
      identity: { system_prompt: "test" },
      circle: makeCircle(),
    });
    const entity = spell.summon();
    expect(entity.llm).toBeDefined();
    expect(entity.identity).toBeDefined();
    expect(entity.circle).toBeDefined();
  });

  test("call with simple system_prompt derives gate_definitions from circle", async () => {
    const llm = makeLlm([
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
      llm: llm as any,
      identity: { system_prompt: "Simple prompt" },
      circle: makeCircle(),
    });

    const result = await spell.cast("test");
    expect(result).toBe("ok");
  });
});
