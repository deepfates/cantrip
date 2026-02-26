// Example 18: VM Medium
// The entity works inside a node:vm sandbox. Full ES2024 — arrow functions,
// async/await, template literals, destructuring. Zero new dependencies.
// Compare with 08_js_medium.ts (QuickJS — limited ES, serialization boundary).

import "./env";
import { cantrip, Circle, ChatAnthropic, max_turns, require_done, vm } from "../src";

export async function main() {
  console.log("=== Example 18: VM Medium ===");
  console.log("The vm medium gives the entity a node:vm sandbox.");
  console.log("Full ES2024. Async/await. No serialization boundary.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  const data = {
    users: [
      { name: "Alice", scores: [95, 87, 92] },
      { name: "Bob", scores: [78, 85, 90] },
      { name: "Carol", scores: [88, 91, 96] },
    ],
  };

  const circle = Circle({
    medium: vm({ state: { context: data } }),
    wards: [max_turns(10), require_done()],
  });

  const spell = cantrip({
    crystal,
    call: "Explore the context variable using code. Use submit_answer() when done.",
    circle,
  });

  try {
    console.log('Asking: "Who has the highest average score?"');
    const answer = await spell.cast("Who has the highest average score? Show your work.");
    console.log(`Answer: ${answer}`);
    return answer;
  } finally {
    await circle.dispose?.();
  }
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
