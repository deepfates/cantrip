import { describe, expect, test } from "bun:test";

import { Agent, TaskComplete } from "../src/agent/service";
import { tool } from "../src/tools/decorator";

async function addHandler({ a, b }: { a: number; b: number }) {
  return a + b;
}

const add = tool("Add", addHandler, {
  name: "add",
  schema: {
    type: "object",
    properties: { a: { type: "integer" }, b: { type: "integer" } },
    required: ["a", "b"],
    additionalProperties: false,
  },
});

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const done = tool("Done", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

describe("agent", () => {
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

    const agent = new Agent({ llm: llm as any, tools: [add] });
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

    const agent = new Agent({
      llm: llm as any,
      tools: [done],
      require_done_tool: true,
    });

    const result = await agent.query("finish");
    expect(result).toBe("all set");
  });

  test("ephemeral tool messages are destroyed", async () => {
    async function ephHandler() {
      return "big output";
    }

    const eph = tool("Ephemeral", ephHandler, {
      name: "ephemeral",
      schema: {
        type: "object",
        properties: {},
        required: [],
        additionalProperties: false,
      },
      ephemeral: 1,
    });

    let step = 0;
    const llm = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async ainvoke(messages: any[]) {
        step += 1;
        if (step <= 2) {
          return {
            content: null,
            tool_calls: [
              {
                id: `call_${step}`,
                type: "function",
                function: {
                  name: "ephemeral",
                  arguments: "{}",
                },
              },
            ],
          };
        }
        return { content: "done", tool_calls: [] };
      },
    };

    const agent = new Agent({ llm: llm as any, tools: [eph] });
    const result = await agent.query("run twice");
    expect(result).toBe("done");

    const toolMessages = agent.history.filter(
      (m) => m.role === "tool",
    ) as any[];
    expect(toolMessages.length).toBe(2);
    expect(toolMessages[0].destroyed).toBe(true);
    expect(toolMessages[1].destroyed).toBe(false);
  });
});
