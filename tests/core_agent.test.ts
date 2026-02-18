import { describe, expect, test } from "bun:test";

import { CoreAgent } from "../src/entity/core";
import { rawTool } from "../src/circle/gate/raw";
import { TaskComplete } from "../src/entity/errors";

const add = rawTool(
  {
    name: "add",
    description: "Add",
    parameters: {
      type: "object",
      properties: { a: { type: "integer" }, b: { type: "integer" } },
      required: ["a", "b"],
      additionalProperties: false,
    },
  },
  async ({ a, b }: { a: number; b: number }) => a + b,
);

const done = rawTool(
  {
    name: "done",
    description: "Done",
    parameters: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"],
      additionalProperties: false,
    },
  },
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
);

describe("core agent", () => {
  test("executes tool calls and returns content", async () => {
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        if (messages.filter((m) => m.role === "tool").length === 0) {
          return {
            content: null,
            tool_calls: [
              {
                id: "call_1",
                type: "function",
                function: {
                  name: "add",
                  arguments: JSON.stringify({ a: 2, b: 3 }),
                },
              },
            ],
          };
        }
        return { content: "Result is 5", tool_calls: [] };
      },
    };

    const agent = new CoreAgent({ llm: llm as any, tools: [add] });
    const result = await agent.query("What is 2 + 3?");
    expect(result).toBe("Result is 5");
  });

  test("require_done_tool waits for done", async () => {
    let callCount = 0;
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        callCount += 1;
        if (callCount === 1) {
          return {
            content: null,
            tool_calls: [
              {
                id: "call_1",
                type: "function",
                function: {
                  name: "done",
                  arguments: JSON.stringify({ message: "all set" }),
                },
              },
            ],
          };
        }
        return { content: "Should not get here", tool_calls: [] };
      },
    };

    const agent = new CoreAgent({
      llm: llm as any,
      tools: [done],
      require_done_tool: true,
    });

    const result = await agent.query("finish");
    expect(result).toBe("all set");
  });

  test("does not retry on errors", async () => {
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke() {
        throw new Error("boom");
      },
    };

    const agent = new CoreAgent({ llm: llm as any, tools: [] });
    await expect(agent.query("hi")).rejects.toThrow("boom");
  });
});
