import { describe, expect, test } from "bun:test";
import { Entity } from "../../../src/cantrip/entity";
import { cantrip } from "../../../src/cantrip/cantrip";
import { TaskComplete } from "../../../src/entity/errors";
import { gate } from "../../../src/circle/gate/decorator";
import { Loom, MemoryStorage } from "../../../src/loom";
import { Circle } from "../../../src/circle/circle";
import { recordCallRoot, recordTurn } from "../../../src/entity/recording";
import { generateTurnId } from "../../../src/loom/turn";
import type { Turn } from "../../../src/loom/turn";
import type { Ward } from "../../../src/circle/ward";
import type { BoundGate } from "../../../src/circle/gate/gate";

// ── Helpers ──────────────────────────────────────────────────────────

async function doneHandler({ message }: { message: string }) {
  throw new TaskComplete(message);
}

const doneGate = gate("Done", doneHandler, {
  name: "done",
  schema: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
    additionalProperties: false,
  },
});

const ward: Ward = { max_turns: 10, require_done_tool: true };

function makeCircle(gates: BoundGate[] = [doneGate], wards = [ward]) {
  return Circle({ gates, wards });
}

function makeLlm(responses: (() => any)[]) {
  let callIndex = 0;
  return {
    model: "dummy",
    provider: "dummy",
    name: "dummy",
    context_window: 128_000,
    async query(messages: any[]) {
      const fn = responses[callIndex];
      if (!fn) throw new Error(`Unexpected LLM call #${callIndex}`);
      callIndex++;
      return fn();
    },
  };
}

// ── Tests ────────────────────────────────────────────────────────────

describe("Loom tree: child entities record into parent loom", () => {
  test("recordCallRoot uses parent_turn_id when provided", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    // Record a parent root
    const parentRootId = await recordCallRoot({
      loom,
      cantrip_id: "parent",
      entity_id: "parent-entity",
      system_prompt: "parent prompt",
      tool_definitions: [],
    });

    // Record a parent turn
    const parentTurnId = await recordTurn({
      loom,
      parent_id: parentRootId,
      cantrip_id: "parent",
      entity_id: "parent-entity",
      turnData: {
        iteration: 1,
        utterance: "I will delegate",
        observation: "call_entity result",
        gate_calls: [{
          gate_name: "call_entity",
          arguments: '{"query":"do stuff"}',
          result: "child result",
          is_error: false,
        }],
        usage: { prompt_tokens: 10, completion_tokens: 5 },
        duration_ms: 100,
        terminated: false,
        truncated: false,
      },
    });

    // Record a child call root with parent_turn_id pointing to the parent's delegation turn
    const childRootId = await recordCallRoot({
      loom,
      cantrip_id: "child",
      entity_id: "child-entity",
      system_prompt: "child prompt",
      tool_definitions: [],
      parent_turn_id: parentTurnId,
    });

    // Verify the child root's parent_id points to the parent's delegation turn
    const childRoot = loom.getTurn(childRootId);
    expect(childRoot).toBeDefined();
    expect(childRoot!.parent_id).toBe(parentTurnId);
    expect(childRoot!.entity_id).toBe("child-entity");
    expect(childRoot!.role).toBe("call");

    // Verify getChildren of parent turn returns child root
    const children = loom.getChildren(parentTurnId);
    expect(children.length).toBe(1);
    expect(children[0].id).toBe(childRootId);
  });

  test("recordCallRoot defaults to null parent_id when no parent_turn_id", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    const rootId = await recordCallRoot({
      loom,
      cantrip_id: "standalone",
      entity_id: "entity-1",
      system_prompt: "test",
      tool_definitions: [],
    });

    const root = loom.getTurn(rootId);
    expect(root!.parent_id).toBeNull();
  });

  test("getThread walks from child leaf through parent to root", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    // Build a tree: parent-root -> parent-turn-1 -> child-root -> child-turn-1
    const parentRootId = await recordCallRoot({
      loom,
      cantrip_id: "parent",
      entity_id: "parent",
      system_prompt: "parent",
      tool_definitions: [],
    });

    const parentTurn1Id = await recordTurn({
      loom,
      parent_id: parentRootId,
      cantrip_id: "parent",
      entity_id: "parent",
      turnData: {
        iteration: 1,
        utterance: "delegating",
        observation: "",
        gate_calls: [],
        usage: undefined,
        duration_ms: 0,
        terminated: false,
        truncated: false,
      },
    });

    const childRootId = await recordCallRoot({
      loom,
      cantrip_id: "child",
      entity_id: "child",
      system_prompt: "child",
      tool_definitions: [],
      parent_turn_id: parentTurn1Id,
    });

    const childTurn1Id = await recordTurn({
      loom,
      parent_id: childRootId,
      cantrip_id: "child",
      entity_id: "child",
      turnData: {
        iteration: 1,
        utterance: "child work",
        observation: "",
        gate_calls: [],
        usage: undefined,
        duration_ms: 0,
        terminated: true,
        truncated: false,
      },
    });

    // getThread from child leaf should walk: child-turn-1 -> child-root -> parent-turn-1 -> parent-root
    const thread = loom.getThread(childTurn1Id);
    expect(thread.length).toBe(4);
    expect(thread[0].id).toBe(parentRootId);
    expect(thread[1].id).toBe(parentTurn1Id);
    expect(thread[2].id).toBe(childRootId);
    expect(thread[3].id).toBe(childTurn1Id);

    // Entity IDs should distinguish parent vs child
    expect(thread[0].entity_id).toBe("parent");
    expect(thread[1].entity_id).toBe("parent");
    expect(thread[2].entity_id).toBe("child");
    expect(thread[3].entity_id).toBe("child");
  });

  test("batch children are siblings under the same parent turn", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    const parentRootId = await recordCallRoot({
      loom,
      cantrip_id: "parent",
      entity_id: "parent",
      system_prompt: "parent",
      tool_definitions: [],
    });

    const parentTurnId = await recordTurn({
      loom,
      parent_id: parentRootId,
      cantrip_id: "parent",
      entity_id: "parent",
      turnData: {
        iteration: 1,
        utterance: "batch delegate",
        observation: "",
        gate_calls: [],
        usage: undefined,
        duration_ms: 0,
        terminated: false,
        truncated: false,
      },
    });

    // Two batch children, both with the same parent turn
    const child1RootId = await recordCallRoot({
      loom,
      cantrip_id: "child-1",
      entity_id: "child-1",
      system_prompt: "child 1",
      tool_definitions: [],
      parent_turn_id: parentTurnId,
    });

    const child2RootId = await recordCallRoot({
      loom,
      cantrip_id: "child-2",
      entity_id: "child-2",
      system_prompt: "child 2",
      tool_definitions: [],
      parent_turn_id: parentTurnId,
    });

    // Both children should be children of the same parent turn
    const children = loom.getChildren(parentTurnId);
    expect(children.length).toBe(2);
    const childIds = children.map((c) => c.id);
    expect(childIds).toContain(child1RootId);
    expect(childIds).toContain(child2RootId);

    // Each child's parent_id points to the same parent turn
    expect(loom.getTurn(child1RootId)!.parent_id).toBe(parentTurnId);
    expect(loom.getTurn(child2RootId)!.parent_id).toBe(parentTurnId);
  });

  test("Entity with parent_turn_id records child call root under parent", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    // Simulate a parent turn already in the loom
    const parentRootId = await recordCallRoot({
      loom,
      cantrip_id: "parent",
      entity_id: "parent",
      system_prompt: "parent",
      tool_definitions: [],
    });

    const parentTurnId = await recordTurn({
      loom,
      parent_id: parentRootId,
      cantrip_id: "parent",
      entity_id: "parent",
      turnData: {
        iteration: 1,
        utterance: "calling child",
        observation: "",
        gate_calls: [],
        usage: undefined,
        duration_ms: 0,
        terminated: false,
        truncated: false,
      },
    });

    // Create a child entity that records into the parent's loom
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [{
          id: "call_1",
          type: "function",
          function: {
            name: "done",
            arguments: JSON.stringify({ message: "child done" }),
          },
        }],
      }),
    ]);

    const childEntity = new Entity({
      crystal: crystal as any,
      call: {
        system_prompt: "child system prompt",
        hyperparameters: { tool_choice: "auto" },
        gate_definitions: [],
      },
      circle: makeCircle(),
      dependency_overrides: null,
      loom,
      cantrip_id: "child-cantrip",
      entity_id: "child-entity",
      parent_turn_id: parentTurnId,
    });

    await childEntity.cast("do something");

    // Verify the loom now contains both parent and child turns
    const allTurns = await storage.getAll();
    // parent root + parent turn + child call root + child turn(s)
    expect(allTurns.length).toBeGreaterThanOrEqual(4);

    // Find the child call root
    const childCallRoot = allTurns.find(
      (t) => t.entity_id === "child-entity" && t.role === "call"
    );
    expect(childCallRoot).toBeDefined();
    expect(childCallRoot!.parent_id).toBe(parentTurnId);

    // The child's subsequent turns should chain from the child call root
    const childTurns = allTurns.filter(
      (t) => t.entity_id === "child-entity" && t.role !== "call"
    );
    expect(childTurns.length).toBeGreaterThanOrEqual(1);
    expect(childTurns[0].parent_id).toBe(childCallRoot!.id);

    // getThread from the child's last turn should walk through to the parent root
    const childLeaf = childTurns[childTurns.length - 1];
    const thread = loom.getThread(childLeaf.id);
    expect(thread[0].entity_id).toBe("parent"); // parent root
    expect(thread[thread.length - 1].entity_id).toBe("child-entity"); // child leaf
  });

  test("Entity lastTurnId getter tracks the most recent turn", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [{
          id: "call_1",
          type: "function",
          function: {
            name: "done",
            arguments: JSON.stringify({ message: "done" }),
          },
        }],
      }),
    ]);

    const entity = new Entity({
      crystal: crystal as any,
      call: {
        system_prompt: "test",
        hyperparameters: { tool_choice: "auto" },
        gate_definitions: [],
      },
      circle: makeCircle(),
      dependency_overrides: null,
      loom,
      cantrip_id: "test",
      entity_id: "test",
    });

    // Before any turn, lastTurnId should be null
    expect(entity.lastTurnId).toBeNull();

    await entity.cast("hello");

    // After a turn, lastTurnId should be set
    expect(entity.lastTurnId).not.toBeNull();

    // It should match the last turn in the loom
    const allTurns = await storage.getAll();
    const lastTurn = allTurns[allTurns.length - 1];
    expect(entity.lastTurnId).toBe(lastTurn.id);
  });

  test("backward compat: child without parent loom creates its own", async () => {
    // This verifies existing behavior: when no loom is passed,
    // the entity creates its own ephemeral loom.
    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [{
          id: "call_1",
          type: "function",
          function: {
            name: "done",
            arguments: JSON.stringify({ message: "standalone" }),
          },
        }],
      }),
    ]);

    // Entity without a loom — should work fine (no recording)
    const entity = new Entity({
      crystal: crystal as any,
      call: {
        system_prompt: "test",
        hyperparameters: { tool_choice: "auto" },
        gate_definitions: [],
      },
      circle: makeCircle(),
      dependency_overrides: null,
      // No loom, no parent_turn_id
    });

    const result = await entity.cast("hello");
    expect(result).toBe("standalone");
  });

  test("cantrip with parent_turn_id creates entity that branches from parent", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    // Pre-populate parent turns
    const parentRootId = await recordCallRoot({
      loom,
      cantrip_id: "parent",
      entity_id: "parent",
      system_prompt: "parent",
      tool_definitions: [],
    });

    const parentTurnId = await recordTurn({
      loom,
      parent_id: parentRootId,
      cantrip_id: "parent",
      entity_id: "parent",
      turnData: {
        iteration: 1,
        utterance: "delegate",
        observation: "",
        gate_calls: [],
        usage: undefined,
        duration_ms: 0,
        terminated: false,
        truncated: false,
      },
    });

    const crystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [{
          id: "call_1",
          type: "function",
          function: {
            name: "done",
            arguments: JSON.stringify({ message: "via cantrip child" }),
          },
        }],
      }),
    ]);

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "child prompt" },
      circle: makeCircle(),
      loom,
      cantrip_id: "child-cantrip",
      parent_turn_id: parentTurnId,
    });

    const entity = spell.invoke();
    await entity.cast("child task");

    // The child's call root should branch from the parent turn
    const allTurns = await storage.getAll();
    const childCallRoot = allTurns.find(
      (t) => t.cantrip_id === "child-cantrip" && t.role === "call"
    );
    expect(childCallRoot).toBeDefined();
    expect(childCallRoot!.parent_id).toBe(parentTurnId);

    // getChildren of parent turn should include the child call root
    const children = loom.getChildren(parentTurnId);
    expect(children.some((c) => c.id === childCallRoot!.id)).toBe(true);
  });

  test("concurrent appends from batch children don't corrupt the loom", async () => {
    const storage = new MemoryStorage();
    const loom = new Loom(storage);

    const parentRootId = await recordCallRoot({
      loom,
      cantrip_id: "parent",
      entity_id: "parent",
      system_prompt: "parent",
      tool_definitions: [],
    });

    // Simulate 8 concurrent child recordings (like call_entity_batch)
    const promises = Array.from({ length: 8 }, (_, i) =>
      (async () => {
        const childRootId = await recordCallRoot({
          loom,
          cantrip_id: `child-${i}`,
          entity_id: `child-${i}`,
          system_prompt: `child ${i}`,
          tool_definitions: [],
          parent_turn_id: parentRootId,
        });

        const childTurnId = await recordTurn({
          loom,
          parent_id: childRootId,
          cantrip_id: `child-${i}`,
          entity_id: `child-${i}`,
          turnData: {
            iteration: 1,
            utterance: `child ${i} work`,
            observation: "",
            gate_calls: [],
            usage: undefined,
            duration_ms: 0,
            terminated: true,
            truncated: false,
          },
        });

        return { childRootId, childTurnId };
      })()
    );

    const results = await Promise.all(promises);

    // Verify all 17 turns exist (1 parent root + 8 child roots + 8 child turns)
    expect(loom.size).toBe(17);

    // Verify all child roots are children of the parent root
    const children = loom.getChildren(parentRootId);
    expect(children.length).toBe(8);

    // Verify each child's thread walks back to the parent root
    for (const { childTurnId } of results) {
      const thread = loom.getThread(childTurnId);
      expect(thread[0].id).toBe(parentRootId);
      expect(thread[0].entity_id).toBe("parent");
    }

    // Verify all turns have unique IDs
    const allTurns = await storage.getAll();
    const ids = new Set(allTurns.map((t) => t.id));
    expect(ids.size).toBe(17);
  });
});
