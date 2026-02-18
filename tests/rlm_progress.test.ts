import { describe, expect, test, afterEach } from "bun:test";
import { createRlmAgent } from "../src/circle/gate/builtin/call_agent";
import { JsAsyncContext } from "../src/circle/gate/builtin/js_async_context";
import type { BaseChatModel } from "../src/crystal/crystal";
import type { AnyMessage } from "../src/crystal/messages";
import type { ChatInvokeCompletion } from "../src/crystal/views";
import type { RlmProgressEvent } from "../src/circle/gate/builtin/call_agent_tools";

class MockLlm implements BaseChatModel {
  model = "mock";
  provider = "mock";
  name = "mock";
  private callCount = 0;

  constructor(
    private responses: ((messages: AnyMessage[]) => ChatInvokeCompletion)[],
  ) {}

  async ainvoke(messages: AnyMessage[]): Promise<ChatInvokeCompletion> {
    const idx = Math.min(this.callCount, this.responses.length - 1);
    this.callCount++;
    const res = this.responses[idx](messages);
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

describe("RLM progress events", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("llm_query emits sub_agent_start and sub_agent_end", async () => {
    const events: RlmProgressEvent[] = [];

    const mockLlm = new MockLlm([
      (msgs) => {
        const last = msgs[msgs.length - 1];
        if (last.content === "Start") {
          return {
            content: "Delegating",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var r = llm_query('child task'); submit_answer(r);",
                  }),
                },
              },
            ],
          };
        }
        if (last.content === "child task") {
          return {
            content: "Child",
            tool_calls: [
              {
                id: "c1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "submit_answer('done');",
                  }),
                },
              },
            ],
          };
        }
        return { content: "?", tool_calls: [] };
      },
    ]);

    const { agent, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: {},
      maxDepth: 1,
      onProgress: (e) => events.push(e),
    });
    activeSandbox = sandbox;

    await agent.query("Start");

    const starts = events.filter((e) => e.type === "sub_agent_start");
    const ends = events.filter((e) => e.type === "sub_agent_end");

    expect(starts).toHaveLength(1);
    expect(starts[0].depth).toBe(1);
    expect((starts[0] as any).query).toBe("child task");

    expect(ends).toHaveLength(1);
    expect(ends[0].depth).toBe(1);
  });

  test("llm_batch emits batch_start, batch_item, and batch_end", async () => {
    const events: RlmProgressEvent[] = [];

    const mockLlm = new MockLlm([
      (msgs) => {
        const last = msgs[msgs.length - 1];
        if (last.role === "user" && last.content === "Start") {
          return {
            content: "Batching",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var r = llm_batch([{query:'q1'}, {query:'q2'}]); submit_answer(r.join(','));",
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
              id: "c" + Math.random(),
              type: "function",
              function: {
                name: "js",
                arguments: JSON.stringify({
                  code: "submit_answer('ok');",
                }),
              },
            },
          ],
        };
      },
    ]);

    const { agent, sandbox } = await createRlmAgent({
      llm: mockLlm,
      context: {},
      maxDepth: 1,
      onProgress: (e) => events.push(e),
    });
    activeSandbox = sandbox;

    await agent.query("Start");

    const batchStarts = events.filter((e) => e.type === "batch_start");
    const batchItems = events.filter((e) => e.type === "batch_item");
    const batchEnds = events.filter((e) => e.type === "batch_end");

    expect(batchStarts).toHaveLength(1);
    expect((batchStarts[0] as any).count).toBe(2);

    expect(batchItems).toHaveLength(2);
    expect((batchItems[0] as any).index).toBe(0);
    expect((batchItems[0] as any).total).toBe(2);
    expect((batchItems[0] as any).query).toBe("q1");
    expect((batchItems[1] as any).index).toBe(1);
    expect((batchItems[1] as any).query).toBe("q2");

    expect(batchEnds).toHaveLength(1);
  });

  test("onProgress defaults to console.error when not provided", async () => {
    const stderrOutput: string[] = [];
    const origError = console.error;
    console.error = (...args: any[]) => stderrOutput.push(args.join(" "));

    try {
      const mockLlm = new MockLlm([
        (msgs) => {
          const last = msgs[msgs.length - 1];
          if (last.content === "Go") {
            return {
              content: "Delegating",
              tool_calls: [
                {
                  id: "p1",
                  type: "function",
                  function: {
                    name: "js",
                    arguments: JSON.stringify({
                      code: "var r = llm_query('sub'); submit_answer(r);",
                    }),
                  },
                },
              ],
            };
          }
          if (last.content === "sub") {
            return {
              content: "Child",
              tool_calls: [
                {
                  id: "c1",
                  type: "function",
                  function: {
                    name: "js",
                    arguments: JSON.stringify({
                      code: "submit_answer('ok');",
                    }),
                  },
                },
              ],
            };
          }
          return { content: "?", tool_calls: [] };
        },
      ]);

      const { agent, sandbox } = await createRlmAgent({
        llm: mockLlm,
        context: {},
        maxDepth: 1,
        // No onProgress — should default to console.error logging
      });
      activeSandbox = sandbox;

      await agent.query("Go");

      // Should have logged sub-agent start/end to stderr
      const hasStart = stderrOutput.some((line) => line.includes("[depth:1]"));
      const hasDone = stderrOutput.some((line) => line.includes("done"));
      expect(hasStart).toBe(true);
      expect(hasDone).toBe(true);
    } finally {
      console.error = origError;
    }
  });
});
