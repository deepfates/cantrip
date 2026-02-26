// Example 14: Recursive entities — depth-limited self-spawning.
// A parent entity in a JS medium delegates subtasks to child entities via call_entity.
// The entity auto-provides spawn (direct LLM query) — no manual wiring needed.
// Medium: js | LLM: Yes | Recursion: Yes

import "./env";
import {
  cantrip, Circle, ChatAnthropic, Loom, MemoryStorage,
  max_turns, require_done, call_entity_gate, js,
} from "../src";

export async function main() {
  console.log("=== Example 14: Recursive Entities ===");
  console.log("A parent entity delegates subtasks to child entities via call_entity.");
  console.log("Depth is limited by the ward — no infinite recursion.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  // Data to analyze — spread across categories so delegation is natural.
  const data = {
    categories: [
      { name: "revenue", items: [100, 250, 175, 300, 225] },
      { name: "costs", items: [80, 120, 95, 140, 110] },
      { name: "headcount", items: [10, 12, 11, 15, 14] },
    ],
  };

  // Build the call_entity gate — at depth 0, max_depth 2.
  // Returns null at max depth, so children can't spawn further children.
  const entityGate = call_entity_gate({ max_depth: 2, depth: 0, parent_context: data });

  // Circle: JS medium + call_entity + wards. done_for_medium is auto-injected.
  const gates = entityGate ? [entityGate] : [];
  const circle = Circle({
    medium: js({ state: { context: data } }),
    gates,
    wards: [max_turns(20), require_done()],
  });

  // Shared loom captures both parent and child turns as a tree.
  const loom = new Loom(new MemoryStorage());

  // The entity auto-prepends capability docs from the circle.
  const spell = cantrip({
    crystal,
    call: "Explore the context variable using code. Use call_entity to delegate sub-intents to child entities. Use submit_answer() when done.",
    circle,
    loom,
  });

  try {
    console.log('Asking: "Analyze each category and summarize the overall trend."');
    const answer = await spell.cast(
      "Analyze each category (revenue, costs, headcount) and summarize the overall trend. " +
      "Use call_entity to delegate analysis of each category to a child entity.",
    );
    console.log(`\nAnswer: ${answer}`);

    // Show the loom tree size.
    console.log(`\nLoom recorded ${loom.size} turns (parent + children).`);

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
