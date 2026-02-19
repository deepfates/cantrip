// cantrip-migration: uses createRlmAgentWithMemory (RLM-internal factory).
// Tests WASM sandbox memory windowing and agent.messages manipulation —
// genuinely below the cantrip API level.
import { describe, test, expect, mock } from "bun:test";
import { createRlmAgentWithMemory } from "../src/circle/gate/builtin/call_agent";
import { BaseChatModel } from "../src/crystal/crystal";
import type { ChatInvokeCompletion } from "../src/crystal/views";

// Mock LLM that responds predictably
function createMockLlm(responses: string[]): BaseChatModel {
  let callIndex = 0;
  return {
    model: "mock",
    provider: "mock",
    name: "mock",
    async ainvoke(): Promise<ChatInvokeCompletion> {
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

describe("RLM Memory", () => {
  test("creates agent with memory support", async () => {
    const llm = createMockLlm(["hello"]);

    const { agent, sandbox, manageMemory } = await createRlmAgentWithMemory({
      llm,
      windowSize: 3,
    });

    expect(agent).toBeDefined();
    expect(sandbox).toBeDefined();
    expect(typeof manageMemory).toBe("function");

    sandbox.dispose();
  });

  test("context starts with empty history", async () => {
    const llm = createMockLlm(["check"]);

    const { sandbox } = await createRlmAgentWithMemory({
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

    const { sandbox } = await createRlmAgentWithMemory({
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
      async ainvoke(): Promise<ChatInvokeCompletion> {
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

    const { agent, sandbox, manageMemory } = await createRlmAgentWithMemory({
      llm,
      windowSize: 2, // Keep only 2 turns in active prompt
    });

    // Simulate 4 turns
    await agent.query("Turn 1");
    manageMemory();

    await agent.query("Turn 2");
    manageMemory();

    // After 2 turns, nothing should be in history yet (within window)
    let result = await sandbox.evalCode("context.history.length");
    expect((result as any).output).toBe("0");

    await agent.query("Turn 3");
    manageMemory();

    // After 3 turns with window=2, turn 1 should be in history
    result = await sandbox.evalCode("context.history.length");
    expect(parseInt((result as any).output)).toBeGreaterThan(0);

    await agent.query("Turn 4");
    manageMemory();

    // With 4 turns and windowSize=2, we should have 2 in history and 2 active
    result = await sandbox.evalCode(
      "context.history.filter(m => m.role === 'user').length",
    );
    const historyUserCount = parseInt((result as any).output);
    expect(historyUserCount).toBe(2);

    const activeUserMessages = agent.messages.filter(
      (m) => m.role === "user",
    ).length;
    expect(activeUserMessages).toBe(2);

    // Total preserved
    expect(historyUserCount + activeUserMessages).toBe(4);

    sandbox.dispose();
  });
});
