// Folding — compress older turns to keep the context window small.
// When a thread gets long, fold early turns into a summary.

import {
  Loom, MemoryStorage, deriveThread,
  shouldFold, partitionForFolding, fold,
  generateTurnId, type Turn, DEFAULT_FOLDING_CONFIG,
  type BaseChatModel,
} from "../src";

export async function main() {
  const loom = new Loom(new MemoryStorage());
  const cantripId = "fold-demo";
  const entityId = "fold-entity";

  // Build a conversation with several turns.
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
        tokens_prompt: 500 * i,
        tokens_completion: 100,
        tokens_cached: 0,
        duration_ms: 300,
        timestamp: new Date().toISOString(),
      },
      reward: null,
      terminated: i === 6,
      truncated: false,
    };
    await loom.append(turn);
    parentId = turn.id;
  }

  // Derive the thread.
  const leaves = loom.getLeaves();
  const thread = deriveThread(loom, leaves[0].id);
  console.log(`Thread: ${thread.turns.length} turns`);

  // Check if folding is needed.
  const totalTokens = thread.turns.reduce(
    (sum, t) => sum + t.metadata.tokens_prompt + t.metadata.tokens_completion,
    0,
  );
  const contextWindow = 4096;
  const config = { ...DEFAULT_FOLDING_CONFIG, enabled: true };

  console.log(`Total tokens: ${totalTokens}, context window: ${contextWindow}`);
  console.log(`Should fold: ${shouldFold(totalTokens, contextWindow, config)}`);

  // Partition into what to fold vs keep.
  const { toFold, toKeep } = partitionForFolding(thread, config);
  console.log(`To fold: ${toFold.length} turns, to keep: ${toKeep.length} turns`);

  // fold() requires a real crystal to summarize — here we just show the partition.
  // In production: const result = await fold(toFold, toKeep, crystal, config);
  console.log("Folding partitioned successfully. Use fold() with a crystal to compress.");
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
