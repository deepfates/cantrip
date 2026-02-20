import { describe, expect, test, beforeEach } from "bun:test";

import { TaskComplete } from "../../src/entity/errors";
import { gate } from "../../src/circle/gate/decorator";
import {
  Loom,
  MemoryStorage,
  generateTurnId,
  deriveThread,
  type Turn,
} from "../../src/loom";
import { cantrip } from "../../src/cantrip/cantrip";
import type { Circle } from "../../src/circle/circle";

// ── Shared helpers ─────────────────────────────────────────────────

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const doneGate = gate("Signal completion", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const echoGate = gate("Echo text back", async ({ text }: { text: string }) => text, {
  name: "echo",
  schema: {
    type: "object",
    properties: { text: { type: "string" } },
    required: ["text"],
    additionalProperties: false,
  },
});

function makeTurn(overrides: Partial<Turn> & { id: string }): Turn {
  return {
    parent_id: null,
    cantrip_id: "test-cantrip",
    entity_id: "test-entity",
    sequence: 1,
    utterance: "",
    observation: "",
    gate_calls: [],
    metadata: {
      tokens_prompt: 0,
      tokens_completion: 0,
      tokens_cached: 0,
      duration_ms: 0,
      timestamp: new Date().toISOString(),
    },
    reward: null,
    terminated: false,
    truncated: false,
    ...overrides,
  };
}

// ── LOOM-1: every turn recorded before next begins ─────────────────

describe("LOOM-1: every turn recorded before next begins", () => {
  test("LOOM-1: loom append records turns in order", async () => {
    const loom = new Loom(new MemoryStorage());

    // Simulate a 3-turn agent run by manually appending turns
    await loom.append(makeTurn({
      id: "t1",
      sequence: 1,
      utterance: "step 1",
      gate_calls: [{ gate_name: "echo", arguments: '{"text":"1"}', result: "1", is_error: false }],
    }));
    await loom.append(makeTurn({
      id: "t2",
      parent_id: "t1",
      sequence: 2,
      utterance: "step 2",
      gate_calls: [{ gate_name: "echo", arguments: '{"text":"2"}', result: "2", is_error: false }],
    }));
    await loom.append(makeTurn({
      id: "t3",
      parent_id: "t2",
      sequence: 3,
      utterance: "done",
      gate_calls: [{ gate_name: "done", arguments: '{"answer":"ok"}', result: "ok", is_error: false }],
      terminated: true,
    }));

    expect(loom.size).toBe(3);
    const thread = loom.getThread("t3");
    expect(thread).toHaveLength(3);
    expect(thread[0].sequence).toBe(1);
    expect(thread[1].sequence).toBe(2);
    expect(thread[2].sequence).toBe(3);
    expect(thread[2].terminated).toBe(true);
  });
});

// ── LOOM-2: turns have unique IDs and parent references ────────────

describe("LOOM-2: turns have unique IDs and parent references", () => {
  test("LOOM-2: each turn has a unique ID", () => {
    const ids = new Set(Array.from({ length: 100 }, () => generateTurnId()));
    expect(ids.size).toBe(100);
  });

  test("LOOM-2: turns form a chain via parent_id", async () => {
    const loom = new Loom(new MemoryStorage());
    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1", sequence: 2 }));
    await loom.append(makeTurn({ id: "t3", parent_id: "t2", sequence: 3 }));

    const thread = loom.getThread("t3");
    expect(thread.map((t) => t.id)).toEqual(["t1", "t2", "t3"]);
    expect(thread[1].parent_id).toBe("t1");
    expect(thread[2].parent_id).toBe("t2");
  });
});

// ── LOOM-3: loom is append-only ────────────────────────────────────

describe("LOOM-3: loom is append-only", () => {
  test("LOOM-3: duplicate turn IDs are rejected", async () => {
    const loom = new Loom(new MemoryStorage());
    await loom.append(makeTurn({ id: "t1" }));
    await expect(loom.append(makeTurn({ id: "t1" }))).rejects.toThrow("already exists");
  });

  test("LOOM-3: reward can be assigned after creation", async () => {
    const loom = new Loom(new MemoryStorage());
    await loom.append(makeTurn({ id: "t1" }));
    await loom.setReward("t1", 1.0);
    expect(loom.getTurn("t1")!.reward).toBe(1.0);
  });
});

// ── LOOM-4: fork from turn N preserves context up to N ─────────────

describe("LOOM-4: fork from turn N preserves context up to N", () => {
  test("LOOM-4: forking creates divergent threads sharing a prefix", async () => {
    const loom = new Loom(new MemoryStorage());

    await loom.append(makeTurn({ id: "t1", sequence: 1, utterance: "A" }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1", sequence: 2, utterance: "B" }));
    await loom.append(makeTurn({ id: "t3", parent_id: "t2", sequence: 3, utterance: "C" }));

    // Fork from t1
    const forkPoint = loom.fork("t1");
    expect(forkPoint.id).toBe("t1");

    await loom.append(makeTurn({ id: "t4", parent_id: "t1", sequence: 2, utterance: "forked" }));

    // Original thread
    const original = loom.getThread("t3");
    expect(original.map((t) => t.id)).toEqual(["t1", "t2", "t3"]);

    // Forked thread shares t1 prefix
    const forked = loom.getThread("t4");
    expect(forked.map((t) => t.id)).toEqual(["t1", "t4"]);

    // Forked thread does NOT include B or C
    const forkedUtterances = forked.map((t) => t.utterance);
    expect(forkedUtterances).not.toContain("B");
    expect(forkedUtterances).not.toContain("C");
  });
});

// ── LOOM-5: folding preserves full history ─────────────────────────

describe("LOOM-5: folding preserves full history", () => {
  test("LOOM-5: loom retains all turns even if context is folded", async () => {
    const loom = new Loom(new MemoryStorage());

    // Build 5 turns
    let parentId: string | null = null;
    for (let i = 1; i <= 5; i++) {
      const id = `t${i}`;
      await loom.append(makeTurn({ id, parent_id: parentId, sequence: i }));
      parentId = id;
    }

    expect(loom.size).toBe(5);

    // Even after any folding, all turns are still in the loom
    const thread = loom.getThread("t5");
    expect(thread).toHaveLength(5);
  });
});

// ── LOOM-7: loom records terminated vs truncated ───────────────────

describe("LOOM-7: loom records terminated vs truncated", () => {
  test("LOOM-7: terminated turn has terminated=true, truncated=false", async () => {
    const loom = new Loom(new MemoryStorage());
    await loom.append(makeTurn({ id: "t1", terminated: true, truncated: false }));
    const turn = loom.getTurn("t1")!;
    expect(turn.terminated).toBe(true);
    expect(turn.truncated).toBe(false);
  });

  test("LOOM-7: truncated turn has terminated=false, truncated=true", async () => {
    const loom = new Loom(new MemoryStorage());
    await loom.append(makeTurn({ id: "t1", terminated: false, truncated: true }));
    const turn = loom.getTurn("t1")!;
    expect(turn.terminated).toBe(false);
    expect(turn.truncated).toBe(true);
  });

  test("LOOM-7: deriveThread reports terminated state", async () => {
    const loom = new Loom(new MemoryStorage());
    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1", sequence: 2, terminated: true }));

    const thread = deriveThread(loom, "t2");
    expect(thread.state).toBe("terminated");
  });

  test("LOOM-7: deriveThread reports truncated state", async () => {
    const loom = new Loom(new MemoryStorage());
    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1", sequence: 2, truncated: true }));

    const thread = deriveThread(loom, "t2");
    expect(thread.state).toBe("truncated");
  });
});

// ── LOOM-8: child turns stored in parent loom ──────────────────────

describe("LOOM-8: child turns stored in parent loom", () => {
  test("LOOM-8: child entity turns branch from parent turn", async () => {
    const loom = new Loom(new MemoryStorage());

    // Parent entity
    await loom.append(makeTurn({
      id: "p1",
      entity_id: "parent",
      sequence: 1,
      utterance: "Starting task",
    }));

    // Child entity branches from p1
    await loom.append(makeTurn({
      id: "c1",
      parent_id: "p1",
      entity_id: "child",
      sequence: 1,
      utterance: "Working on subtask",
    }));
    await loom.append(makeTurn({
      id: "c2",
      parent_id: "c1",
      entity_id: "child",
      sequence: 2,
      utterance: "Subtask done",
      terminated: true,
    }));

    // Parent continues
    await loom.append(makeTurn({
      id: "p2",
      parent_id: "p1",
      entity_id: "parent",
      sequence: 2,
      utterance: "Continuing after child",
      terminated: true,
    }));

    // Child thread
    const childThread = loom.getThread("c2");
    expect(childThread.map((t) => t.entity_id)).toEqual(["parent", "child", "child"]);

    // Parent thread
    const parentThread = loom.getThread("p2");
    expect(parentThread.map((t) => t.entity_id)).toEqual(["parent", "parent"]);

    // Both threads share p1
    expect(childThread[0].id).toBe("p1");
    expect(parentThread[0].id).toBe("p1");
  });
});

// ── LOOM-9: turns record token usage and timing ────────────────────

describe("LOOM-9: turns record token usage and timing", () => {
  test("LOOM-9: turn metadata stores all token counts, cached tokens, duration, and timestamp", async () => {
    const loom = new Loom(new MemoryStorage());

    await loom.append(makeTurn({
      id: "t1",
      metadata: {
        tokens_prompt: 100,
        tokens_completion: 50,
        tokens_cached: 20,
        duration_ms: 250,
        timestamp: "2024-01-01T00:00:00.000Z",
      },
    }));

    const turn = loom.getTurn("t1")!;
    expect(turn.metadata.tokens_prompt).toBe(100);
    expect(turn.metadata.tokens_completion).toBe(50);
    expect(turn.metadata.tokens_cached).toBe(20);
    expect(turn.metadata.duration_ms).toBe(250);
    expect(turn.metadata.timestamp).toBe("2024-01-01T00:00:00.000Z");
  });
});

// ── LOOM-10: thread extraction produces trajectory ─────────────────

describe("LOOM-10: thread extraction produces trajectory", () => {
  test("LOOM-10: getThread returns complete root-to-leaf path", async () => {
    const loom = new Loom(new MemoryStorage());

    await loom.append(makeTurn({
      id: "t1",
      sequence: 1,
      utterance: "step 1",
      observation: "result 1",
    }));
    await loom.append(makeTurn({
      id: "t2",
      parent_id: "t1",
      sequence: 2,
      utterance: "step 2",
      observation: "result 2",
    }));
    await loom.append(makeTurn({
      id: "t3",
      parent_id: "t2",
      sequence: 3,
      utterance: "step 3",
      observation: "result 3",
      terminated: true,
    }));

    const thread = loom.getThread("t3");
    expect(thread).toHaveLength(3);

    // Each turn has utterance and observation
    for (const turn of thread) {
      expect(turn.utterance).toBeDefined();
      expect(turn.observation).toBeDefined();
    }

    // Last turn is terminated
    expect(thread[2].terminated).toBe(true);
  });

  test("LOOM-10: deriveThread returns trajectory with state", async () => {
    const loom = new Loom(new MemoryStorage());

    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1", sequence: 2 }));
    await loom.append(makeTurn({
      id: "t3",
      parent_id: "t2",
      sequence: 3,
      terminated: true,
    }));

    const thread = deriveThread(loom, "t3");
    expect(thread.state).toBe("terminated");
    expect(thread.leafId).toBe("t3");
    expect(thread.turns).toHaveLength(3);
  });
});
