// Example 10: Composition — batch delegation via call_entity_batch.
// A parent entity splits work across child entities that run in parallel.
// Each child gets independent context and a fresh circle.
// Medium: js | LLM: Yes | Recursion: Yes (depth 1)

import "./env";
import {
  cantrip, Circle, Loom, MemoryStorage,
  max_turns, require_done,
  call_entity_gate, call_entity_batch_gate,
  ChatOpenAI,
} from "../src";
import { js } from "../src/circle/medium/js";

export async function main() {
  console.log("=== Example 10: Composition ===");
  console.log("A parent entity delegates subtasks to children via call_entity_batch.");
  console.log("Children run in parallel, each with independent context.\n");

  const crystal = new ChatOpenAI({ model: "gpt-5-mini" });

  // Data to analyze — three documents, each best handled by a focused child.
  const data = {
    documents: [
      { id: 1, title: "Q1 Revenue", content: "Revenue grew 15% YoY to $4.2M. SaaS ARR reached $3.1M. Enterprise deals drove 60% of new bookings." },
      { id: 2, title: "Q1 Costs", content: "Total OpEx was $3.8M, up 8%. Headcount grew from 42 to 47. Infrastructure costs fell 12% after migration." },
      { id: 3, title: "Q1 Outlook", content: "Pipeline is $12M, up 25%. Two enterprise deals expected to close in Q2. Hiring plan: 5 engineers, 2 sales." },
    ],
  };

  // Build delegation gates — call_entity for single, call_entity_batch for parallel
  const entityGate = call_entity_gate({ max_depth: 1, depth: 0, parent_context: data });
  const batchGate = call_entity_batch_gate({ max_depth: 1, depth: 0, parent_context: data });
  const gates = [entityGate, batchGate].filter(Boolean) as any[];

  const circle = Circle({
    medium: js({ state: { context: data } }),
    gates,
    wards: [max_turns(20), require_done()],
  });

  // Shared loom captures parent + child turns as a tree.
  const loom = new Loom(new MemoryStorage());

  const spell = cantrip({
    crystal,
    call: "Analyze documents by delegating to child entities. Use call_entity_batch to process documents in parallel. Synthesize the results into a coherent summary. Use submit_answer() when done.",
    circle,
    loom,
  });

  try {
    console.log('Asking: "Summarize each document, then give an overall analysis."');
    const answer = await spell.cast(
      "Summarize each document in context.documents, then synthesize an overall analysis. " +
      "Use call_entity_batch to delegate each document summary to a child entity.",
    );
    console.log(`\nAnswer: ${answer}`);
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
