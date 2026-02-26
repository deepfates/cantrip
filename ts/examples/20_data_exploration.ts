// Example 20: Data Exploration (RLM Pattern)
// Load real data into the medium via state. Entity explores through code.
// This is the Recursive Language Model pattern: data in sandbox, LLM writes
// code to explore it. The viewport forces compositional behavior — data stays
// in variables, not the prompt.

import "./env";
import { cantrip, Circle, ChatAnthropic, max_turns, require_done, vm } from "../src";

// Synthetic dataset — in practice this could be loaded from a file or API
const SALES_DATA = Array.from({ length: 50 }, (_, i) => ({
  id: i + 1,
  product: ["Widget A", "Widget B", "Gadget X", "Gadget Y", "Service Z"][i % 5],
  region: ["North", "South", "East", "West"][i % 4],
  quarter: `Q${(i % 4) + 1}`,
  revenue: Math.round(1000 + Math.random() * 9000),
  units: Math.round(10 + Math.random() * 90),
}));

export async function main() {
  console.log("=== Example 20: Data Exploration ===");
  console.log("50 sales records injected as a global. Entity explores via code.");
  console.log("The viewport shows [Result: N chars] — data lives in variables.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  const circle = Circle({
    medium: vm({ state: { sales: SALES_DATA } }),
    wards: [max_turns(15), require_done()],
  });

  const spell = cantrip({
    crystal,
    call: "You are a data analyst. The `sales` variable contains an array of sales records. Explore it with code — group, filter, aggregate. Use submit_answer() with your findings.",
    circle,
  });

  try {
    const answer = await spell.cast(
      "Analyze the sales data: which product has the highest total revenue? " +
      "Which region performs best? Are there any quarterly trends?"
    );
    console.log(`Analysis:\n${answer}`);
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
