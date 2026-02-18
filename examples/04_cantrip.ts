// Cantrip — the full recipe. crystal + call + circle = cantrip.
// Cast a cantrip on an intent, an entity arises.

import "./env";
import { cantrip, Circle, ChatAnthropic, done, tool, max_turns } from "../src";

const add = tool("Add two numbers", async ({ a, b }: { a: number; b: number }) => a + b, {
  name: "add",
  params: { a: "number", b: "number" },
});

async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  const circle = Circle({
    gates: [add, done],
    wards: [max_turns(10)],
  });

  // Bind the recipe.
  const spell = cantrip({
    crystal,
    call: { system_prompt: "You are a calculator. Use the add tool, then call done with the result." },
    circle,
  });

  // Cast on an intent → an entity runs and returns the result.
  const result = await spell.cast("What is 2 + 3?");
  console.log("Result:", result);

  // Cast again → independent entity, no shared state (CANTRIP-2).
  const result2 = await spell.cast("What is 10 + 20?");
  console.log("Result 2:", result2);
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
