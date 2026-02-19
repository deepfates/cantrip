// Example 01: Crystal
// A crystal wraps an LLM. You give it messages, it returns a response.
// This is the simplest building block — just an API call.

import "./env";
import { ChatAnthropic, type ChatInvokeCompletion } from "../src";

export async function main() {
  console.log("=== Example 01: Crystal ===");
  console.log("A Crystal wraps an LLM. You give it messages, it returns a response.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  console.log('Asking: "What is 2+2? Reply with just the number."');
  const result: ChatInvokeCompletion = await crystal.ainvoke([
    { role: "user", content: "What is 2 + 2? Reply with just the number." },
  ]);

  console.log(`Response: ${result.content}`);
  console.log("\nThe crystal returned a single response — it's just an LLM call.");

  return result.content;
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
