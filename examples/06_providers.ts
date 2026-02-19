// Providers — same cantrip, different crystal.
// Swap the crystal to use any supported LLM provider.

import "./env";
import {
  cantrip, Circle, done, tool, max_turns,
  ChatAnthropic, ChatOpenAI, ChatGoogle, ChatOpenRouter, ChatLMStudio,
} from "../src";

const add = tool("Add two numbers", async ({ a, b }: { a: number; b: number }) => a + b, {
  name: "add",
  params: { a: "number", b: "number" },
});

export async function main() {
  const circle = Circle({
    gates: [add, done],
    wards: [max_turns(10)],
  });

  const call = { system_prompt: "You are a calculator. Use add, then call done." };

  // Pick a crystal — the rest of the cantrip stays the same.
  const crystals = {
    anthropic: () => new ChatAnthropic({ model: "claude-sonnet-4-5" }),
    openai: () => new ChatOpenAI({ model: "gpt-5-mini" }),
    google: () => new ChatGoogle({ model: "gemini-3-flash-preview" }),
    openrouter: () => new ChatOpenRouter({ model: "anthropic/claude-sonnet-4-5" }),
    lmstudio: () => new ChatLMStudio({ model: "local-model" }),
  };

  const provider = (process.argv[2] as keyof typeof crystals) || "anthropic";
  const crystal = crystals[provider]?.() ?? crystals.anthropic();
  console.log(`Using crystal: ${crystal.name} (${crystal.model})`);

  const spell = cantrip({ crystal, call, circle });
  const result = await spell.cast("What is 7 + 8?");
  console.log("Result:", result);
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
