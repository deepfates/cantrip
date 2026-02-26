import { describe, expect, test, afterEach } from "bun:test";
import { createRlmAgent } from "../src/rlm/service";
import { JsAsyncContext } from "../src/tools/builtin/js_async_context";
import type { BaseChatModel } from "../src/llm/base";
import type { AnyMessage } from "../src/llm/messages";
import type { ChatInvokeCompletion } from "../src/llm/views";

/**
 * Mock LLM that can simulate RLM behaviors.
 * Responses are sequential by default, or can be determined by inspecting messages.
 */
class MockRlmLlm implements BaseChatModel {
  model = "mock-rlm";
  provider = "mock";
  name = "mock-rlm";
  private callCount = 0;

  constructor(
    private responses: ((messages: AnyMessage[]) => ChatInvokeCompletion)[],
  ) {}

  async ainvoke(messages: AnyMessage[]): Promise<ChatInvokeCompletion> {
    const idx = Math.min(this.callCount, this.responses.length - 1);
    const responseFn = this.responses[idx];
    this.callCount++;
    const res = responseFn(messages);
    return {
      ...res,
      usage: res.usage ?? {
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
      },
    };
  }
}

describe("RLM Integration", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("Metadata Loop: Model sees metadata, not full content in history", async () => {
    const hugeContext = "A".repeat(100000);

    const mockLlm = new MockRlmLlm([
      () => ({
        content: "Step 1",
        tool_calls: [
          {
            id: "c1",
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({ code: "context.length" }),
            },
          },
        ],
      }),
      (messages) => {
        const toolMsg = messages.find((m) => m.role === "tool") as any;
        const toolContent = toolMsg?.content || "";
        // Metadata check: history should contain the length string but not the massive "A" sequence
        if (toolContent.includes("100000") && !toolContent.includes("AAAAA")) {
          return {
            content: "Success",
            tool_calls: [
              {
                id: "c2",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "submit_answer('History is clean')",
                  }),
                },
              },
            ],
          };
        }
        return { content: "Failed: " + toolContent, tool_calls: [] };
      },
    ]);

    const { agent, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: hugeContext,
    });
    activeSandbox = sandbox;
    const result = await agent.query("test");
    expect(result).toBe("History is clean");
  });

  test("Recursion: llm_query spawns a child agent and returns result", async () => {
    const mockLlm = new MockRlmLlm([
      (msgs) => {
        const lastMsg = msgs[msgs.length - 1];
        if (lastMsg.role === "user" && lastMsg.content === "Start") {
          return {
            content: "Parent",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var res = llm_query('Get Secret'); submit_answer(res);",
                  }),
                },
              },
            ],
          };
        }
        if (lastMsg.role === "user" && lastMsg.content === "Get Secret") {
          return {
            content: "Child Result",
            tool_calls: [
              {
                id: "child1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "submit_answer(context.secret);",
                  }),
                },
              },
            ],
          };
        }
        return { content: "Error", tool_calls: [] };
      },
    ]);

    const { agent, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: { secret: "password123" },
      maxDepth: 1,
    });
    activeSandbox = sandbox;

    const result = await agent.query("Start");
    expect(result).toBe("password123");

    // Verify token aggregation: Parent tracker should see both its tokens and child's
    const usage = await agent.get_usage();
    // 1 parent call + 1 child call = 2 calls * 10 prompt tokens = 20
    expect(usage.total_prompt_tokens).toBeGreaterThanOrEqual(20);
  });

  test("Recursion Depth Limit: llm_query falls back to plain LLM call", async () => {
    const mockLlm = new MockRlmLlm([
      () => ({
        content: "Level 0",
        tool_calls: [
          {
            id: "L0",
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: "var res = llm_query('L1'); submit_answer(res);",
              }),
            },
          },
        ],
      }),
      () => ({
        content: "Level 1",
        tool_calls: [
          {
            id: "L1",
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: "var res = llm_query('L2'); submit_answer(res);",
              }),
            },
          },
        ],
      }),
      () => ({
        content: "Max Depth Reached",
        tool_calls: [],
      }),
    ]);

    const { agent, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "data",
      maxDepth: 1,
    });
    activeSandbox = sandbox;

    const result = await agent.query("Start");
    expect(result).toBe("Max Depth Reached");
  });

  test("submit_answer: Correctly extracts and stringifies complex objects", async () => {
    const mockLlm = new MockRlmLlm([
      () => ({
        content: "Calculating...",
        tool_calls: [
          {
            id: "c1",
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: "var obj = { a: 1, b: [2, 3] }; submit_answer(obj);",
              }),
            },
          },
        ],
      }),
    ]);

    const { agent, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: {},
    });
    activeSandbox = sandbox;

    const result = await agent.query("Start");
    const parsed = JSON.parse(result);
    expect(parsed.a).toBe(1);
    expect(parsed.b).toEqual([2, 3]);
  });

  test("Context Isolation: Child cannot modify parent context", async () => {
    const mockLlm = new MockRlmLlm([
      (msgs) => {
        const lastMsg = msgs[msgs.length - 1];
        if (lastMsg.content === "Start") {
          return {
            content: "Parent",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "llm_query('Change'); submit_answer(context.data);",
                  }),
                },
              },
            ],
          };
        }
        if (lastMsg.content === "Change") {
          return {
            content: "Child",
            tool_calls: [
              {
                id: "c1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "context.data = 'changed'; submit_answer('ok');",
                  }),
                },
              },
            ],
          };
        }
        return { content: "Error", tool_calls: [] };
      },
    ]);

    const { agent, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: { data: "original" },
      maxDepth: 1,
    });
    activeSandbox = sandbox;

    const result = await agent.query("Start");
    // Parent's context should still be 'original' despite child's attempt to mutate
    expect(result).toBe("original");
  });

  test("Batching: llm_batch executes multiple sub-queries in parallel", async () => {
    const mockLlm = new MockRlmLlm([
      (msgs) => {
        const lastMsg = msgs[msgs.length - 1];
        if (lastMsg.role === "user" && lastMsg.content === "Start") {
          return {
            content: "Parent batching",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var results = llm_batch([{query:'t', context:'a'}, {query:'t', context:'b'}]); submit_answer(results.join(', '));",
                  }),
                },
              },
            ],
          };
        }
        return {
          content: "Child",
          tool_calls: [
            {
              id: "c_" + Math.random(),
              type: "function",
              function: {
                name: "js",
                arguments: JSON.stringify({
                  code: "submit_answer('Result for ' + context)",
                }),
              },
            },
          ],
        };
      },
    ]);

    const { agent, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: "parent",
      maxDepth: 1,
    });
    activeSandbox = sandbox;

    const result = await agent.query("Start");
    expect(result).toBe("Result for a, Result for b");

    // Verify token aggregation for batch
    const usage = await agent.get_usage();
    // 1 parent call + 2 parallel child calls = 3 calls * 10 prompt tokens = 30
    expect(usage.total_prompt_tokens).toBeGreaterThanOrEqual(30);
  });
});
