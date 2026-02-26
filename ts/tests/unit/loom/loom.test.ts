import { describe, expect, test, beforeEach, afterEach } from "bun:test";
import { promises as fs } from "fs";
import { tmpdir } from "os";
import path from "path";

import {
  Loom,
  MemoryStorage,
  JsonlStorage,
  type Turn,
  generateTurnId,
  deriveThread,
  threadToMessages,
  shouldFold,
  partitionForFolding,
  fold,
  DEFAULT_FOLDING_CONFIG,
} from "../../../src/loom";

/** Helper: create a Turn with minimal required fields. */
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

describe("Turn", () => {
  test("generateTurnId produces unique IDs", () => {
    const ids = new Set(Array.from({ length: 100 }, () => generateTurnId()));
    expect(ids.size).toBe(100);
  });

  test("generateTurnId starts with 'turn-'", () => {
    expect(generateTurnId()).toMatch(/^turn-/);
  });
});

describe("Loom with MemoryStorage", () => {
  let loom: Loom;

  beforeEach(() => {
    loom = new Loom(new MemoryStorage());
  });

  test("append and retrieve a turn", async () => {
    const turn = makeTurn({ id: "t1", utterance: "hello" });
    await loom.append(turn);
    expect(loom.getTurn("t1")).toEqual(turn);
    expect(loom.size).toBe(1);
  });

  test("rejects duplicate turn IDs", async () => {
    await loom.append(makeTurn({ id: "t1" }));
    await expect(loom.append(makeTurn({ id: "t1" }))).rejects.toThrow(
      "already exists",
    );
  });

  test("getRoots returns root turns", async () => {
    await loom.append(makeTurn({ id: "r1" }));
    await loom.append(makeTurn({ id: "r2" }));
    await loom.append(makeTurn({ id: "c1", parent_id: "r1" }));
    const roots = loom.getRoots();
    expect(roots.map((t) => t.id)).toEqual(["r1", "r2"]);
  });

  test("getChildren returns direct children", async () => {
    await loom.append(makeTurn({ id: "r1" }));
    await loom.append(makeTurn({ id: "c1", parent_id: "r1" }));
    await loom.append(makeTurn({ id: "c2", parent_id: "r1" }));
    const children = loom.getChildren("r1");
    expect(children.map((t) => t.id)).toEqual(["c1", "c2"]);
  });

  test("getThread returns root-to-leaf path", async () => {
    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1", sequence: 2 }));
    await loom.append(makeTurn({ id: "t3", parent_id: "t2", sequence: 3 }));

    const thread = loom.getThread("t3");
    expect(thread.map((t) => t.id)).toEqual(["t1", "t2", "t3"]);
  });

  test("getThread throws for unknown turn", () => {
    expect(() => loom.getThread("nonexistent")).toThrow("not found");
  });

  test("getLeaves returns turns with no children", async () => {
    await loom.append(makeTurn({ id: "t1" }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1" }));
    await loom.append(makeTurn({ id: "t3", parent_id: "t1" }));
    const leaves = loom.getLeaves();
    expect(leaves.map((t) => t.id).sort()).toEqual(["t2", "t3"]);
  });

  test("fork returns the fork point turn", async () => {
    await loom.append(makeTurn({ id: "t1" }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1" }));
    const forkPoint = loom.fork("t1");
    expect(forkPoint.id).toBe("t1");
  });

  test("fork throws for unknown turn", () => {
    expect(() => loom.fork("nonexistent")).toThrow("not found");
  });

  test("forking creates divergent threads", async () => {
    // Build a linear thread: t1 -> t2 -> t3
    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    await loom.append(makeTurn({ id: "t2", parent_id: "t1", sequence: 2 }));
    await loom.append(makeTurn({ id: "t3", parent_id: "t2", sequence: 3 }));

    // Fork from t2 to create an alternative branch
    const forkPoint = loom.fork("t2");
    await loom.append(
      makeTurn({ id: "t4", parent_id: forkPoint.id, sequence: 3 }),
    );

    // Original thread
    const original = loom.getThread("t3");
    expect(original.map((t) => t.id)).toEqual(["t1", "t2", "t3"]);

    // Forked thread shares the prefix
    const forked = loom.getThread("t4");
    expect(forked.map((t) => t.id)).toEqual(["t1", "t2", "t4"]);
  });

  test("setReward updates turn reward", async () => {
    await loom.append(makeTurn({ id: "t1" }));
    await loom.setReward("t1", 0.95);
    expect(loom.getTurn("t1")!.reward).toBe(0.95);
  });

  test("setReward throws for unknown turn", async () => {
    await expect(loom.setReward("nonexistent", 1.0)).rejects.toThrow(
      "not found",
    );
  });
});

describe("Loom with JsonlStorage", () => {
  let tempDir: string;
  let jsonlPath: string;

  beforeEach(async () => {
    tempDir = await fs.mkdtemp(path.join(tmpdir(), "loom-test-"));
    jsonlPath = path.join(tempDir, "loom.jsonl");
  });

  afterEach(async () => {
    await fs.rm(tempDir, { recursive: true, force: true });
  });

  test("persists and loads turns from JSONL", async () => {
    const storage = new JsonlStorage(jsonlPath);
    const loom1 = new Loom(storage);

    await loom1.append(makeTurn({ id: "t1", utterance: "hello" }));
    await loom1.append(
      makeTurn({ id: "t2", parent_id: "t1", utterance: "world" }),
    );

    // Create a new loom instance and load from the same file
    const loom2 = new Loom(new JsonlStorage(jsonlPath));
    await loom2.load();

    expect(loom2.size).toBe(2);
    expect(loom2.getTurn("t1")!.utterance).toBe("hello");
    expect(loom2.getTurn("t2")!.utterance).toBe("world");

    const thread = loom2.getThread("t2");
    expect(thread.map((t) => t.id)).toEqual(["t1", "t2"]);
  });

  test("handles missing JSONL file gracefully", async () => {
    const storage = new JsonlStorage(path.join(tempDir, "nonexistent.jsonl"));
    const loom = new Loom(storage);
    await loom.load();
    expect(loom.size).toBe(0);
  });
});

describe("Thread derivation", () => {
  let loom: Loom;

  beforeEach(() => {
    loom = new Loom(new MemoryStorage());
  });

  test("deriveThread returns correct state for terminated thread", async () => {
    await loom.append(
      makeTurn({ id: "t1", sequence: 1, utterance: "starting" }),
    );
    await loom.append(
      makeTurn({
        id: "t2",
        parent_id: "t1",
        sequence: 2,
        utterance: "done",
        terminated: true,
      }),
    );

    const thread = deriveThread(loom, "t2");
    expect(thread.state).toBe("terminated");
    expect(thread.leafId).toBe("t2");
    expect(thread.turns).toHaveLength(2);
  });

  test("deriveThread returns truncated state", async () => {
    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    await loom.append(
      makeTurn({
        id: "t2",
        parent_id: "t1",
        sequence: 2,
        truncated: true,
      }),
    );

    const thread = deriveThread(loom, "t2");
    expect(thread.state).toBe("truncated");
  });

  test("deriveThread returns active state", async () => {
    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    const thread = deriveThread(loom, "t1");
    expect(thread.state).toBe("active");
  });

  test("threadToMessages converts turns to crystal messages", async () => {
    await loom.append(
      makeTurn({
        id: "t1",
        sequence: 1,
        utterance: "I will read the file",
        observation: "File contents here",
        gate_calls: [
          {
            gate_name: "read_file",
            arguments: '{"path":"/tmp/test.txt"}',
            result: "File contents here",
            is_error: false,
          },
        ],
      }),
    );
    await loom.append(
      makeTurn({
        id: "t2",
        parent_id: "t1",
        sequence: 2,
        utterance: "The file contains test data",
        observation: "",
        terminated: true,
      }),
    );

    const thread = deriveThread(loom, "t2");
    const messages = threadToMessages(thread);

    // t1: assistant (with tool_calls) + tool result + user (observation)
    // t2: assistant (utterance only, no observation)
    expect(messages.length).toBe(4);
    expect(messages[0].role).toBe("assistant");
    expect(messages[1].role).toBe("tool");
    expect(messages[2].role).toBe("user");
    expect(messages[3].role).toBe("assistant");
  });
});

describe("Folding", () => {
  test("shouldFold returns true when above threshold", () => {
    const config = { ...DEFAULT_FOLDING_CONFIG, threshold_ratio: 0.8 };
    expect(shouldFold(90000, 100000, config)).toBe(true);
    expect(shouldFold(70000, 100000, config)).toBe(false);
  });

  test("shouldFold returns false when disabled", () => {
    const config = { ...DEFAULT_FOLDING_CONFIG, enabled: false };
    expect(shouldFold(90000, 100000, config)).toBe(false);
  });

  test("partitionForFolding splits correctly", async () => {
    const loom = new Loom(new MemoryStorage());
    // Build 10 turns
    let parentId: string | null = null;
    for (let i = 1; i <= 10; i++) {
      const id = `t${i}`;
      await loom.append(makeTurn({ id, parent_id: parentId, sequence: i }));
      parentId = id;
    }

    const thread = deriveThread(loom, "t10");
    const config = { ...DEFAULT_FOLDING_CONFIG, recent_turns_to_keep: 3 };
    const { toFold, toKeep } = partitionForFolding(thread, config);

    expect(toFold).toHaveLength(7);
    expect(toKeep).toHaveLength(3);
    expect(toFold[0].id).toBe("t1");
    expect(toKeep[0].id).toBe("t8");
  });

  test("partitionForFolding keeps all when too few turns", async () => {
    const loom = new Loom(new MemoryStorage());
    await loom.append(makeTurn({ id: "t1", sequence: 1 }));
    await loom.append(
      makeTurn({ id: "t2", parent_id: "t1", sequence: 2 }),
    );

    const thread = deriveThread(loom, "t2");
    const config = { ...DEFAULT_FOLDING_CONFIG, recent_turns_to_keep: 5 };
    const { toFold, toKeep } = partitionForFolding(thread, config);

    expect(toFold).toHaveLength(0);
    expect(toKeep).toHaveLength(2);
  });

  test("fold produces a summary and preserves turn IDs", async () => {
    const dummyLLM = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        return {
          content: "<summary>Folded summary of earlier turns</summary>",
          tool_calls: [],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        };
      },
    };

    const turnsToFold = [
      makeTurn({ id: "t1", sequence: 1, utterance: "hello" }),
      makeTurn({ id: "t2", sequence: 2, utterance: "world" }),
      makeTurn({ id: "t3", sequence: 3, utterance: "foo" }),
    ];
    const turnsToKeep = [
      makeTurn({ id: "t4", sequence: 4, utterance: "recent" }),
    ];

    const result = await fold(
      turnsToFold,
      turnsToKeep,
      dummyLLM as any,
    );

    expect(result.folded).toBe(true);
    expect(result.fold_record).not.toBeNull();
    expect(result.fold_record!.folded_turn_ids).toEqual(["t1", "t2", "t3"]);
    expect(result.fold_record!.summary).toBe(
      "Folded summary of earlier turns",
    );
    expect(result.fold_record!.from_sequence).toBe(1);
    expect(result.fold_record!.to_sequence).toBe(3);
    // 1 summary + 1 recent turn (utterance only, observation is empty) = 2 messages
    expect(result.messages).toHaveLength(2);
    expect((result.messages[0] as any).content).toContain("[Folded: turns 1-3]");
    // Recent turn preserved verbatim (SPEC §6.8)
    expect((result.messages[1] as any).role).toBe("assistant");
    expect((result.messages[1] as any).content).toBe("recent");
  });

  test("fold returns no-op when nothing to fold", async () => {
    const dummyLLM = { model: "dummy", async query() { return { content: "" }; } };
    const result = await fold([], [makeTurn({ id: "t1" })], dummyLLM as any);
    expect(result.folded).toBe(false);
    expect(result.fold_record).toBeNull();
  });
});

describe("CALL-4: Call as loom root", () => {
  let loom: Loom;

  beforeEach(() => {
    loom = new Loom(new MemoryStorage());
  });

  test("call root turn is the root of the thread", async () => {
    const callRoot = makeTurn({
      id: "call-root",
      sequence: 0,
      role: "call",
      utterance: "You are a helpful assistant.",
      observation: "- read_file: Read a file\n- write_file: Write a file",
    });
    await loom.append(callRoot);

    const turn1 = makeTurn({
      id: "t1",
      parent_id: "call-root",
      sequence: 1,
      utterance: "I will read the file",
      observation: "File contents here",
      gate_calls: [
        {
          gate_name: "read_file",
          arguments: '{"path":"/tmp/test.txt"}',
          result: "File contents here",
          is_error: false,
        },
      ],
    });
    await loom.append(turn1);

    const thread = deriveThread(loom, "t1");
    expect(thread.turns).toHaveLength(2);
    expect(thread.turns[0].id).toBe("call-root");
    expect(thread.turns[0].role).toBe("call");
    expect(thread.turns[1].id).toBe("t1");
  });

  test("threadToMessages emits system message for call root", async () => {
    await loom.append(
      makeTurn({
        id: "call-root",
        sequence: 0,
        role: "call",
        utterance: "You are a helpful assistant.",
        observation: "- read_file: Read a file",
      }),
    );
    await loom.append(
      makeTurn({
        id: "t1",
        parent_id: "call-root",
        sequence: 1,
        utterance: "Hello!",
        observation: "",
        terminated: true,
      }),
    );

    const thread = deriveThread(loom, "t1");
    const messages = threadToMessages(thread);

    expect(messages[0].role).toBe("system");
    expect((messages[0] as any).content).toBe("You are a helpful assistant.");
    expect(messages[1].role).toBe("assistant");
    expect((messages[1] as any).content).toBe("Hello!");
  });

  test("forked threads share the same call root", async () => {
    await loom.append(
      makeTurn({
        id: "call-root",
        sequence: 0,
        role: "call",
        utterance: "System prompt",
        observation: "",
      }),
    );
    await loom.append(
      makeTurn({ id: "t1", parent_id: "call-root", sequence: 1, utterance: "Branch A" }),
    );
    await loom.append(
      makeTurn({ id: "t2", parent_id: "call-root", sequence: 1, utterance: "Branch B" }),
    );

    const threadA = deriveThread(loom, "t1");
    const threadB = deriveThread(loom, "t2");

    expect(threadA.turns[0].id).toBe("call-root");
    expect(threadB.turns[0].id).toBe("call-root");
    expect(threadA.turns[0].role).toBe("call");
    expect(threadB.turns[0].role).toBe("call");
  });

  test("backward compat: threads without call root still work", async () => {
    await loom.append(makeTurn({ id: "t1", sequence: 1, utterance: "hello" }));
    await loom.append(
      makeTurn({ id: "t2", parent_id: "t1", sequence: 2, utterance: "world", terminated: true }),
    );

    const thread = deriveThread(loom, "t2");
    const messages = threadToMessages(thread);

    expect(messages[0].role).toBe("assistant");
    expect((messages[0] as any).content).toBe("hello");
    expect(messages[1].role).toBe("assistant");
    expect((messages[1] as any).content).toBe("world");
  });
});

describe("Loom tree structure", () => {
  test("composition: child entity turns branch from parent", async () => {
    // LOOM-8: Child entity turns stored in same loom
    const loom = new Loom(new MemoryStorage());

    // Parent entity thread
    await loom.append(
      makeTurn({
        id: "p1",
        entity_id: "parent",
        sequence: 1,
        utterance: "Starting task",
      }),
    );
    await loom.append(
      makeTurn({
        id: "p2",
        parent_id: "p1",
        entity_id: "parent",
        sequence: 2,
        utterance: "Calling child agent",
        gate_calls: [{
          gate_name: "call_entity",
          arguments: '{"task":"subtask"}',
          result: "spawned child",
          is_error: false,
        }],
      }),
    );

    // Child entity subtree branches from p2
    await loom.append(
      makeTurn({
        id: "c1",
        parent_id: "p2",
        entity_id: "child",
        cantrip_id: "test-cantrip",
        sequence: 1,
        utterance: "Working on subtask",
      }),
    );
    await loom.append(
      makeTurn({
        id: "c2",
        parent_id: "c1",
        entity_id: "child",
        sequence: 2,
        utterance: "Subtask done",
        terminated: true,
      }),
    );

    // Parent continues after child
    await loom.append(
      makeTurn({
        id: "p3",
        parent_id: "p2",
        entity_id: "parent",
        sequence: 3,
        utterance: "Child returned, continuing",
        terminated: true,
      }),
    );

    // Parent thread goes through p1, p2, p3
    const parentThread = loom.getThread("p3");
    expect(parentThread.map((t) => t.id)).toEqual(["p1", "p2", "p3"]);

    // Child thread branches from p2
    const childThread = loom.getThread("c2");
    expect(childThread.map((t) => t.id)).toEqual(["p1", "p2", "c1", "c2"]);

    // p2 has two children (child branch + parent continuation)
    const p2Children = loom.getChildren("p2");
    expect(p2Children.map((t) => t.id).sort()).toEqual(["c1", "p3"]);
  });
});
