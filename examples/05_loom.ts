// Loom — inspect the execution record after a cast.
// The loom is an append-only tree of turns. Derive threads, fork branches.

import {
  Loom, MemoryStorage, deriveThread, threadToMessages,
  generateTurnId, type Turn,
} from "../src";

export async function main() {
  const loom = new Loom(new MemoryStorage());

  const cantripId = "demo-cantrip";
  const entityId = "demo-entity";

  // Simulate two turns (in a real cast, the entity records these automatically).
  const turn1: Turn = {
    id: generateTurnId(),
    parent_id: null,
    cantrip_id: cantripId,
    entity_id: entityId,
    sequence: 1,
    utterance: "Let me calculate that.",
    observation: "What is 2 + 3?",
    gate_calls: [{
      gate_name: "add",
      arguments: JSON.stringify({ a: 2, b: 3 }),
      result: "5",
      is_error: false,
    }],
    metadata: {
      tokens_prompt: 150, tokens_completion: 30, tokens_cached: 0,
      duration_ms: 450, timestamp: new Date().toISOString(),
    },
    reward: null,
    terminated: false,
    truncated: false,
  };

  const turn2: Turn = {
    id: generateTurnId(),
    parent_id: turn1.id,
    cantrip_id: cantripId,
    entity_id: entityId,
    sequence: 2,
    utterance: "The result is 5.",
    observation: "",
    gate_calls: [],
    metadata: {
      tokens_prompt: 200, tokens_completion: 15, tokens_cached: 100,
      duration_ms: 320, timestamp: new Date().toISOString(),
    },
    reward: null,
    terminated: true,
    truncated: false,
  };

  await loom.append(turn1);
  await loom.append(turn2);
  console.log(`Loom: ${loom.size} turns`);

  // Derive a thread from the leaf.
  const leaves = loom.getLeaves();
  const thread = deriveThread(loom, leaves[0].id);
  console.log(`Thread: ${thread.turns.length} turns, state=${thread.state}`);

  // Convert to messages (for replaying through a crystal).
  const messages = threadToMessages(thread);
  console.log(`Messages: ${messages.length}`);

  // Fork from turn 1 to create an alternate branch.
  const fork = loom.fork(turn1.id);
  const altTurn: Turn = {
    id: generateTurnId(),
    parent_id: fork.id,
    cantrip_id: cantripId,
    entity_id: "alt-entity",
    sequence: 2,
    utterance: "Let me also try 10 + 20.",
    observation: "What else?",
    gate_calls: [{
      gate_name: "add",
      arguments: JSON.stringify({ a: 10, b: 20 }),
      result: "30",
      is_error: false,
    }],
    metadata: {
      tokens_prompt: 180, tokens_completion: 25, tokens_cached: 50,
      duration_ms: 380, timestamp: new Date().toISOString(),
    },
    reward: null,
    terminated: false,
    truncated: false,
  };
  await loom.append(altTurn);

  console.log(`After fork: ${loom.size} turns, ${loom.getLeaves().length} branches`);
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
