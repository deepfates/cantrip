// Crystal — pick a model, invoke it directly.
// A crystal is the LLM that powers an entity's reasoning.

import { ChatAnthropic, type ChatInvokeCompletion } from "../src";

async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  // Crystals implement ainvoke() — send messages, get a completion.
  const result: ChatInvokeCompletion = await crystal.ainvoke([
    { role: "user", content: "What is 2 + 2? Reply with just the number." },
  ]);

  console.log(result.content);
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
