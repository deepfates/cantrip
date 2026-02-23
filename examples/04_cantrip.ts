// Example 04: Cantrip
// crystal + call + circle = cantrip. Cast it on an intent, an entity arises.
// This is the full recipe — everything before was ingredients.

import "./env";
import { cantrip, Circle, ChatAnthropic, done, gate, max_turns } from "../src";

const add = gate("Add two numbers", async ({ a, b }: { a: number; b: number }) => a + b, {
  name: "add",
  params: { a: "number", b: "number" },
});

export async function main() {
  console.log("=== Example 04: Cantrip ===");
  console.log("A cantrip binds crystal + call + circle. Cast on an intent → entity runs.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  const circle = Circle({
    gates: [add, done],
    wards: [max_turns(10)],
  });

  const spell = cantrip({
    crystal,
    call: { system_prompt: "You are a calculator. Use the add tool, then call done with the result." },
    circle,
  });

  console.log('Casting: "What is 2 + 3?"');
  const result = await spell.cast("What is 2 + 3?");
  console.log(`Result: ${result}`);

  console.log('\nCasting again: "What is 10 + 20?" (independent entity, no shared state)');
  const result2 = await spell.cast("What is 10 + 20?");
  console.log(`Result: ${result2}`);

  console.log("\nEach cast creates a fresh entity — the cantrip is reusable.");

  return { result, result2 };
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
