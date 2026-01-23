import { Agent } from "../src/agent/service";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { rawTool } from "../src/tools/raw";

const echo = rawTool(
  {
    name: "echo",
    description: "Echo input",
    parameters: {
      type: "object",
      properties: { text: { type: "string" } },
      required: ["text"],
      additionalProperties: false,
    },
  },
  async ({ text }: { text: string }) => text,
);

const agent = new Agent({
  llm: new ChatAnthropic({ model: "claude-sonnet-4-20250514" }),
  tools: [echo],
  retry: { enabled: false },
  ephemerals: { enabled: false },
  compaction_enabled: false,
});

export async function main() {
  const result = await agent.query("say hi");
  console.log(result);
  return result;
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
