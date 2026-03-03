// Example 06: Providers
// Same cantrip, different crystal. Swap the crystal to use any LLM provider.
// The cantrip script stays the same — only the model changes.

import "./env";
import {
  cantrip,
  Circle,
  done,
  gate,
  max_turns,
  type BaseChatModel,
  ChatAnthropic,
  ChatOpenAI,
  ChatGoogle,
  ChatOpenRouter,
  ChatLMStudio,
} from "../src";

const add = gate(
  "Add two numbers",
  async ({ a, b }: { a: number; b: number }) => a + b,
  {
    name: "add",
    params: { a: "number", b: "number" },
  },
);

export async function main() {
  console.log("=== Example 06: Providers ===");
  console.log(
    "The same cantrip works with any crystal. Only the model changes.\n",
  );

  const circle = Circle({
    gates: [add, done],
    wards: [max_turns(10)],
  });

  const call = {
    system_prompt: "You are a calculator. Use add, then call done.",
  };

  const crystals = {
    anthropic: () => new ChatAnthropic({ model: "claude-sonnet-4-5" }),
    openai: () => new ChatOpenAI({ model: "gpt-5-mini" }),
    google: () => new ChatGoogle({ model: "gemini-3-flash-preview" }),
    openrouter: () =>
      new ChatOpenRouter({ model: "anthropic/claude-sonnet-4-5" }),
    lmstudio: () => new ChatLMStudio({ model: "local-model" }),
  };

  const fakeLlm: BaseChatModel = {
    model: "fake-provider",
    provider: "fake",
    name: "fake-provider",
    async ainvoke(messages) {
      const lastTool = [...messages].reverse().find((m: any) => m.role === "tool");
      if (lastTool) {
        return {
          content: null,
          tool_calls: [{
            id: "done_1",
            type: "function",
            function: { name: "done", arguments: JSON.stringify({ message: String(lastTool.content) }) },
          }],
        } as any;
      }
      return {
        content: null,
        tool_calls: [{
          id: "add_1",
          type: "function",
          function: { name: "add", arguments: JSON.stringify({ a: 7, b: 8 }) },
        }],
      } as any;
    },
    query(messages, tools, tool_choice) {
      return this.ainvoke(messages, tools, tool_choice);
    },
  };

  const useFake = process.env.CANTRIP_FAKE_LLM === "1";
  const provider = (process.argv[2] as keyof typeof crystals) || "anthropic";
  const crystal = useFake ? fakeLlm : (crystals[provider]?.() ?? crystals.anthropic());
  console.log(`Using llm: ${crystal.name} (${crystal.model})`);

  const spell = cantrip({ llm: crystal, identity: call, circle });
  const result = await spell.cast("What is 7 + 8?");
  console.log(`Result: ${result}`);

  console.log("\nSwap the llm: crystal, keep everything else.");

  return String(result);
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
