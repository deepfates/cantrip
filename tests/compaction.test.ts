import { describe, expect, test } from "bun:test";

import {
  fold,
  shouldFold,
  partitionForFolding,
  DEFAULT_FOLDING_CONFIG,
  type FoldingConfig,
} from "../src/loom/folding";
import type { Turn } from "../src/loom/turn";
import type { Thread } from "../src/loom/thread";

function makeTurn(overrides: Partial<Turn> & { id: string; sequence: number }): Turn {
  return {
    parent_id: null,
    cantrip_id: "test",
    entity_id: "test",
    utterance: `Turn ${overrides.sequence} utterance`,
    observation: `Turn ${overrides.sequence} observation`,
    gate_calls: [],
    metadata: {
      tokens_prompt: 10,
      tokens_completion: 5,
      tokens_cached: 0,
      duration_ms: 100,
      timestamp: new Date().toISOString(),
    },
    reward: null,
    terminated: false,
    truncated: false,
    ...overrides,
  };
}

const dummyLLM = {
  model: "dummy-model",
  provider: "dummy",
  name: "dummy",
  async ainvoke() {
    return {
      content: "<summary>Short summary</summary>",
      tool_calls: [],
      usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
    };
  },
};

describe("folding", () => {
  test("shouldFold returns false when disabled", () => {
    const config: FoldingConfig = { ...DEFAULT_FOLDING_CONFIG, enabled: false };
    expect(shouldFold(100_000, 128_000, config)).toBe(false);
  });

  test("shouldFold returns true when tokens exceed threshold", () => {
    const config: FoldingConfig = { ...DEFAULT_FOLDING_CONFIG, threshold_ratio: 0.5 };
    expect(shouldFold(65_000, 128_000, config)).toBe(true);
  });

  test("shouldFold returns false when tokens below threshold", () => {
    const config: FoldingConfig = { ...DEFAULT_FOLDING_CONFIG, threshold_ratio: 0.8 };
    expect(shouldFold(50_000, 128_000, config)).toBe(false);
  });

  test("partitionForFolding keeps recent turns", () => {
    const turns = Array.from({ length: 10 }, (_, i) =>
      makeTurn({ id: `t${i}`, sequence: i + 1 }),
    );
    const thread: Thread = { turns, state: "active", leafId: "t9" };
    const config: FoldingConfig = { ...DEFAULT_FOLDING_CONFIG, recent_turns_to_keep: 3 };

    const { toFold, toKeep } = partitionForFolding(thread, config);
    expect(toFold.length).toBe(7);
    expect(toKeep.length).toBe(3);
    expect(toKeep[0].id).toBe("t7");
  });

  test("partitionForFolding returns empty toFold when few turns", () => {
    const turns = [makeTurn({ id: "t0", sequence: 1 }), makeTurn({ id: "t1", sequence: 2 })];
    const thread: Thread = { turns, state: "active", leafId: "t1" };
    const config: FoldingConfig = { ...DEFAULT_FOLDING_CONFIG, recent_turns_to_keep: 5 };

    const { toFold, toKeep } = partitionForFolding(thread, config);
    expect(toFold.length).toBe(0);
    expect(toKeep.length).toBe(2);
  });

  test("fold extracts summary tags", async () => {
    const toFold = [makeTurn({ id: "t0", sequence: 1 }), makeTurn({ id: "t1", sequence: 2 })];
    const toKeep = [makeTurn({ id: "t2", sequence: 3 })];

    const result = await fold(toFold, toKeep, dummyLLM as any);
    expect(result.folded).toBe(true);
    expect(result.fold_record).not.toBeNull();
    expect(result.fold_record!.summary).toBe("Short summary");
    expect(result.fold_record!.folded_turn_ids).toEqual(["t0", "t1"]);
    expect(result.fold_record!.from_sequence).toBe(1);
    expect(result.fold_record!.to_sequence).toBe(2);
  });

  test("fold returns folded=false when nothing to fold", async () => {
    const result = await fold([], [makeTurn({ id: "t0", sequence: 1 })], dummyLLM as any);
    expect(result.folded).toBe(false);
    expect(result.fold_record).toBeNull();
  });

  test("fold replaces folded turns with summary message and keeps recent turns", async () => {
    const toFold = [makeTurn({ id: "t0", sequence: 1 })];
    const toKeep = [makeTurn({ id: "t1", sequence: 2 })];

    const result = await fold(toFold, toKeep, dummyLLM as any);
    // Summary message + recent turn messages (utterance + observation)
    expect(result.messages.length).toBe(3);
    expect(result.messages[0].content).toContain("Folded: turns 1-1");
    expect(result.messages[0].content).toContain("Short summary");
    // Recent turn preserved verbatim
    expect(result.messages[1].role).toBe("assistant");
    expect(result.messages[1].content).toBe("Turn 2 utterance");
    expect(result.messages[2].role).toBe("user");
    expect(result.messages[2].content).toBe("Turn 2 observation");
  });

  test("fold preserves multiple recent turns verbatim (SPEC §6.8)", async () => {
    const toFold = [
      makeTurn({ id: "t0", sequence: 1 }),
      makeTurn({ id: "t1", sequence: 2 }),
      makeTurn({ id: "t2", sequence: 3 }),
    ];
    const toKeep = [
      makeTurn({ id: "t3", sequence: 4 }),
      makeTurn({ id: "t4", sequence: 5 }),
    ];

    const result = await fold(toFold, toKeep, dummyLLM as any);
    expect(result.folded).toBe(true);
    expect(result.fold_record!.folded_turn_ids).toEqual(["t0", "t1", "t2"]);
    expect(result.fold_record!.from_sequence).toBe(1);
    expect(result.fold_record!.to_sequence).toBe(3);

    // 1 summary + 2 recent turns * 2 messages each (utterance + observation) = 5
    expect(result.messages.length).toBe(5);
    expect(result.messages[0].content).toContain("Folded: turns 1-3");

    // First recent turn (sequence 4)
    expect(result.messages[1].role).toBe("assistant");
    expect(result.messages[1].content).toBe("Turn 4 utterance");
    expect(result.messages[2].role).toBe("user");
    expect(result.messages[2].content).toBe("Turn 4 observation");

    // Second recent turn (sequence 5)
    expect(result.messages[3].role).toBe("assistant");
    expect(result.messages[3].content).toBe("Turn 5 utterance");
    expect(result.messages[4].role).toBe("user");
    expect(result.messages[4].content).toBe("Turn 5 observation");

    expect(result.original_turn_count).toBe(5);
    expect(result.remaining_turn_count).toBe(2);
  });
});
