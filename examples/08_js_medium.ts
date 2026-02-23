// Example 08: JS Medium
// The entity works inside a QuickJS sandbox. Gates are projected as host functions.
// ONE medium per circle — the medium REPLACES conversation.

import "./env";
import { cantrip, Circle, ChatAnthropic, max_turns, require_done } from "../src";
import { js } from "../src/circle/medium/js";

export async function main() {
  console.log("=== Example 08: JS Medium ===");
  console.log("The JS medium gives the entity a QuickJS sandbox to work in.");
  console.log("Data is injected as globals; the entity explores it with code.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  const data = {
    items: [
      { name: "alpha", value: 10 },
      { name: "beta", value: 25 },
      { name: "gamma", value: 7 },
    ],
  };

  const circle = Circle({
    medium: js({ state: { context: data } }),
    wards: [max_turns(20), require_done()],
  });

  // The entity auto-prepends capability docs from the circle.
  // This call string is pure strategy.
  const spell = cantrip({
    crystal,
    call: "Explore the context variable using the js tool. Use submit_answer() when you have a final answer.",
    circle,
  });

  try {
    console.log('Asking: "Which item has the highest value?"');
    const answer = await spell.cast("Which item has the highest value? Return its name.");
    console.log(`Answer: ${answer}`);
    console.log("\nThe entity wrote JS code to find the answer in the sandbox.");
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
