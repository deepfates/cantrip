// Example 11: Folding — compress older turns to keep the context window small.
// When a thread gets long, fold early turns into a summary.
// LLM: No (mock — folding is demonstrated without calling an LLM)

import {
  Loom, MemoryStorage, deriveThread,
  shouldFold, partitionForFolding,
  generateTurnId, type Turn, DEFAULT_FOLDING_CONFIG,
} from "../src";

export async function main() {
  console.log("--- Example 11: Folding ---");
  console.log("When a thread gets long, folding compresses early turns into a summary.");

  const loom = new Loom(new MemoryStorage());
  const cantripId = "fold-demo";
  const entityId = "fold-entity";

  let parentId: string | null = null;
  for (let i = 1; i <= 6; i++) {
    const turn: Turn = {
      id: generateTurnId(),
      parent_id: parentId,
      cantrip_id: cantripId,
      entity_id: entityId,
      sequence: i,
      utterance: `Response to turn ${i}`,
      observation: `User message ${i}`,
      gate_calls: [],
      metadata: {
        tokens_prompt: 500 * i, tokens_completion: 100, tokens_cached: 0,
        duration_ms: 300, timestamp: new Date().toISOString(),
      },
      reward: null,
      terminated: i === 6,
      truncated: false,
    };
    await loom.append(turn);
    parentId = turn.id;
  }

  const leaves = loom.getLeaves();
  const thread = deriveThread(loom, leaves[0].id);
  const turnCount = thread.turns.length;
  console.log(`Built a thread with ${turnCount} turns.`);

  const totalTokens = thread.turns.reduce(
    (sum, t) => sum + t.metadata.tokens_prompt + t.metadata.tokens_completion,
    0,
  );
  const contextWindow = 4096;
  const config = { ...DEFAULT_FOLDING_CONFIG, enabled: true };
  const needsFolding = shouldFold(totalTokens, contextWindow, config);

  console.log(`Total tokens: ${totalTokens}, context window: ${contextWindow}`);
  console.log(`Should fold: ${needsFolding}`);

  const { toFold, toKeep } = partitionForFolding(thread, config);
  console.log(`Partition: ${toFold.length} turns to fold, ${toKeep.length} to keep.`);
  console.log("Done. In production, fold() would call a crystal to summarize the folded turns.");

  return { turnCount, totalTokens, needsFolding, foldCount: toFold.length, keepCount: toKeep.length };
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
