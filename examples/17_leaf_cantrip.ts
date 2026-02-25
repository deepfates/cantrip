// Example 17: Leaf Cantrip
// Crystal + call, no circle. The simplest possible cantrip — a single LLM call.
// No gates, no medium, no wards. Intent in, answer out.

import "./env";
import { cantrip, Circle, ChatAnthropic, max_turns } from "../src";

export async function main() {
  console.log("=== Example 17: Leaf Cantrip ===");
  console.log("A leaf cantrip has a minimal circle — just crystal + call + max_turns(1).");
  console.log("One LLM call. Cheapest possible delegation.\n");

  const crystal = new ChatAnthropic({ model: "claude-haiku-4-5" });

  // Minimal circle — no gates, no medium. max_turns(1) = single response.
  const spell = cantrip({
    crystal,
    call: "You are a concise summarizer. Respond in one sentence.",
    circle: Circle({ wards: [max_turns(1)] }),
  });

  console.log("Casting: summarize a paragraph");
  const result = await spell.cast(
    "The Familiar pattern gives an entity a JS sandbox with cantrip construction " +
    "gates projected into it. The entity writes code that builds and casts child " +
    "cantrips. Each cast() blocks — the child runs its entire loop and the result " +
    "comes back as a string. Variables persist between turns, so the entity builds " +
    "up state incrementally in the sandbox."
  );
  console.log(`Result: ${result}`);

  // Cast again — independent, no shared state
  console.log("\nCasting again: different intent, same cantrip");
  const result2 = await spell.cast(
    "Explain what A = (M + G) - W means in the context of agent architecture."
  );
  console.log(`Result: ${result2}`);

  return { result, result2 };
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
