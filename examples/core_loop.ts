import { CoreAgent } from "../src/agent/core";
import { rawTool } from "../src/tools/raw";

const add = rawTool(
  {
    name: "add",
    description: "Add two numbers",
    parameters: {
      type: "object",
      properties: {
        a: { type: "integer" },
        b: { type: "integer" },
      },
      required: ["a", "b"],
      additionalProperties: false,
    },
  },
  async ({ a, b }: { a: number; b: number }) => a + b,
);

const agent = new CoreAgent({
  llm: {
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
  },
  tools: [add],
});

async function main() {
  const result = await agent.query("What is 2 + 3?");
  console.log(result);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
