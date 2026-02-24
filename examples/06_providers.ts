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

  const provider = (process.argv[2] as keyof typeof crystals) || "anthropic";
  const crystal = crystals[provider]?.() ?? crystals.anthropic();
  console.log(`Using crystal: ${crystal.name} (${crystal.model})`);

  const spell = cantrip({ crystal, call, circle });
  const result = await spell.cast("What is 7 + 8?");
  console.log(`Result: ${result}`);

  console.log("\nSwap the crystal, keep everything else.");

  return result;
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
