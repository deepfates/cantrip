// Tests WASM sandbox memory windowing and entity.history manipulation
// using cantrip() composition.
import { describe, test, expect, mock } from "bun:test";
import { BaseChatModel } from "../src/crystal/crystal";
import type { AnyMessage } from "../src/crystal/messages";
import type { ChatInvokeCompletion } from "../src/crystal/views";
import { cantrip } from "../src/cantrip/cantrip";
import { Circle } from "../src/circle/circle";
import { js, getJsMediumSandbox } from "../src/circle/medium/js";
import { max_turns, require_done } from "../src/circle/ward";
import { call_entity, call_entity_batch } from "../src/circle/gate/builtin/call_entity_gate";
import { done_for_medium } from "../src/circle/gate/builtin/done";
import { JsAsyncContext } from "../src/circle/medium/js/async_context";
import type { Entity } from "../src/cantrip/entity";

type MemoryAgent = {
  entity: Entity;
  sandbox: JsAsyncContext;
  manageMemory: () => void;
};

/**
 * Local helper for memory-windowing tests.
 * Creates an entity with sliding-window memory management.
 */
async function createTestAgentWithMemory(opts: {
  llm: BaseChatModel;
  data?: unknown;
  windowSize: number;
}): Promise<MemoryAgent> {
  const { llm, data, windowSize } = opts;

  const context: { data: unknown; history: AnyMessage[] } = {
    data: data ?? null,
    history: [],
  };

  const medium = js({ state: { context } });
  const gates = [done_for_medium()];
  const entityGate = call_entity({ max_depth: 2, depth: 0, parent_context: context });
  if (entityGate) gates.push(entityGate);
  const batchGate = call_entity_batch({ max_depth: 2, depth: 0, parent_context: context });
  if (batchGate) gates.push(batchGate);

  const circle = Circle({ medium, gates, wards: [max_turns(20), require_done()] });

  const spell = cantrip({
    crystal: llm,
    call: "Conversational agent with persistent memory. Use submit_answer() to respond.",
    circle,
  });
  const entity = spell.invoke();

  // Init medium AFTER entity so spawnBinding is available
  await medium.init(gates, entity.dependency_overrides);
  const sandbox = getJsMediumSandbox(medium)!;

  // Memory management function — slides old turns into context.history
  const manageMemory = () => {
    while (true) {
      let messages = entity.history;
      const activeUserCount = messages.filter((m) => m.role === "user").length;
      if (activeUserCount <= windowSize) break;
      const startIndex = messages[0]?.role === "system" ? 1 : 0;
      let cutIndex = startIndex;
      while (cutIndex < messages.length && messages[cutIndex].role !== "user") cutIndex++;
      if (cutIndex >= messages.length) break;
      cutIndex++;
      while (cutIndex < messages.length && messages[cutIndex].role !== "user") cutIndex++;
      if (cutIndex <= startIndex) break;
      const toMove = messages.slice(startIndex, cutIndex);
      context.history.push(...toMove);
      messages = [
        ...(startIndex === 1 ? [messages[0]] : []),
        ...messages.slice(cutIndex),
      ];
      entity.load_history(messages);
    }
    sandbox.setGlobal("context", context);
  };

  return { entity, sandbox, manageMemory };
}

// Mock LLM that responds predictably
function createMockLlm(responses: string[]): BaseChatModel {
  let callIndex = 0;
  return {
    model: "mock",
    provider: "mock",
    name: "mock",
    async query(): Promise<ChatInvokeCompletion> {
      const response = responses[callIndex % responses.length];
      callIndex++;

      // Simple response - just submit an answer
      return {
        content: null,
        tool_calls: [
          {
            id: `call_${callIndex}`,
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: `submit_answer("Response ${callIndex}: ${response}")`,
              }),
            },
          },
        ],
      };
    },
  } as BaseChatModel;
}

describe("JS Entity Memory", () => {
  test("creates entity with memory support", async () => {
    const llm = createMockLlm(["hello"]);

    const { entity, sandbox, manageMemory } = await createTestAgentWithMemory({
      llm,
      windowSize: 3,
    });

    expect(entity).toBeDefined();
    expect(sandbox).toBeDefined();
    expect(typeof manageMemory).toBe("function");

    sandbox.dispose();
  });

  test("context starts with empty history", async () => {
    const llm = createMockLlm(["check"]);

    const { sandbox } = await createTestAgentWithMemory({
      llm,
      windowSize: 3,
    });

    // Check context structure via sandbox
    const result = await sandbox.evalCode(
      "JSON.stringify({ hasData: context.data !== null, historyLength: context.history.length })",
    );
    expect(result.ok).toBe(true);

    const parsed = JSON.parse((result as any).output);
    expect(parsed.hasData).toBe(false);
    expect(parsed.historyLength).toBe(0);

    sandbox.dispose();
  });

  test("context includes provided data", async () => {
    const llm = createMockLlm(["check"]);

    const testData = { foo: "bar", items: [1, 2, 3] };

    const { sandbox } = await createTestAgentWithMemory({
      llm,
      data: testData,
      windowSize: 3,
    });

    const result = await sandbox.evalCode(
      "JSON.stringify({ data: context.data, historyLength: context.history.length })",
    );
    expect(result.ok).toBe(true);

    const parsed = JSON.parse((result as any).output);
    expect(parsed.data).toEqual(testData);
    expect(parsed.historyLength).toBe(0);

    sandbox.dispose();
  });

  test("manageMemory moves old messages to context.history", async () => {
    // LLM that just submits simple answers
    let callCount = 0;
    const llm = {
      model: "mock",
      provider: "mock",
      name: "mock",
      async query(): Promise<ChatInvokeCompletion> {
        callCount++;
        return {
          content: null,
          tool_calls: [
            {
              id: `call_${callCount}`,
              type: "function",
              function: {
                name: "js",
                arguments: JSON.stringify({
                  code: `submit_answer("Answer ${callCount}")`,
                }),
              },
            },
          ],
        };
      },
    } as BaseChatModel;

    const { entity, sandbox, manageMemory } = await createTestAgentWithMemory({
      llm,
      windowSize: 2, // Keep only 2 turns in active prompt
    });

    // Simulate 4 turns
    await entity.cast("Turn 1");
    manageMemory();

    await entity.cast("Turn 2");
    manageMemory();

    // After 2 turns, nothing should be in history yet (within window)
    let result = await sandbox.evalCode("context.history.length");
    expect((result as any).output).toBe("0");

    await entity.cast("Turn 3");
    manageMemory();

    // After 3 turns with window=2, turn 1 should be in history
    result = await sandbox.evalCode("context.history.length");
    expect(parseInt((result as any).output)).toBeGreaterThan(0);

    await entity.cast("Turn 4");
    manageMemory();

    // With 4 turns and windowSize=2, we should have 2 in history and 2 active
    result = await sandbox.evalCode(
      "context.history.filter(m => m.role === 'user').length",
    );
    const historyUserCount = parseInt((result as any).output);
    expect(historyUserCount).toBe(2);

    const activeUserMessages = entity.history.filter(
      (m) => m.role === "user",
    ).length;
    expect(activeUserMessages).toBe(2);

    // Total preserved
    expect(historyUserCount + activeUserMessages).toBe(4);

    sandbox.dispose();
  });
});
