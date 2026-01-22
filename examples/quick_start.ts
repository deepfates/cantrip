import { Agent, TaskComplete } from "../src/agent/service";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { tool } from "../src/tools/decorator";

const add = tool(
  "Add two numbers",
  async ({ a, b }: { a: number; b: number }) => a + b,
  {
    name: "add",
    schema: {
      type: "object",
      properties: {
        a: { type: "integer" },
        b: { type: "integer" },
      },
      required: ["a", "b"],
      additionalProperties: false,
    },
  },
);

const done = tool(
  "Signal task completion",
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
  {
    name: "done",
    schema: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"],
      additionalProperties: false,
    },
  },
);

const agent = new Agent({
  llm: new ChatAnthropic({ model: "claude-sonnet-4-20250514" }),
  tools: [add, done],
});

async function main() {
  const result = await agent.query("What is 2 + 3?");
  console.log(result);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
