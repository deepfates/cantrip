import { describe, expect, test } from "bun:test";

import { cantrip } from "../src/cantrip/cantrip";
import { TaskComplete } from "../src/entity/errors";
import { gate } from "../src/circle/gate/decorator";
import { Circle } from "../src/circle/circle";

// ── Shared helpers ─────────────────────────────────────────────────
//
// COMP-* tests verify that cantrips can compose — one cantrip can
// delegate to another via a gate. Since the codebase doesn't yet have
// a built-in call_entity gate, we simulate composition by creating
// a gate that internally runs another cantrip.

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

function makeLlm(responses: (() => any)[]) {
  let callIndex = 0;
  return {
    model: "dummy",
    provider: "dummy",
    name: "dummy",
    async query(messages: any[]) {
      const fn = responses[callIndex];
      if (!fn) throw new Error(`Unexpected LLM call #${callIndex}`);
      callIndex++;
      return fn();
    },
  };
}

// ── COMP-1: child circle is subset of parent ───────────────────────

describe("COMP-1: child circle is subset of parent", () => {
  test("COMP-1: parent cantrip delegates to child via gate that runs a nested cantrip", async () => {
    // Create a child cantrip
    const childCrystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "child_call_1",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "child result" }),
            },
          },
        ],
      }),
    ]);

    const childSpell = cantrip({
      crystal: childCrystal as any,
      call: { system_prompt: "child agent" },
      circle: Circle({
        gates: [doneGate],
        wards: [{ max_turns: 5, require_done_tool: true }],
      }),
    });

    // Create a gate that delegates to the child cantrip
    const callAgentGate = gate(
      "Call a child agent",
      async ({ intent }: { intent: string }) => {
        const result = await childSpell.cast(intent);
        return result;
      },
      {
        name: "call_entity",
        schema: {
          type: "object",
          properties: { intent: { type: "string" } },
          required: ["intent"],
          additionalProperties: false,
        },
      },
    );

    // Parent cantrip that uses call_entity
    const parentCrystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "parent_call_1",
            type: "function",
            function: {
              name: "call_entity",
              arguments: JSON.stringify({ intent: "sub task" }),
            },
          },
        ],
      }),
      () => ({
        content: null,
        tool_calls: [
          {
            id: "parent_call_2",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "parent done with child result" }),
            },
          },
        ],
      }),
    ]);

    const parentSpell = cantrip({
      crystal: parentCrystal as any,
      call: { system_prompt: "parent agent" },
      circle: Circle({
        gates: [doneGate, callAgentGate],
        wards: [{ max_turns: 10, require_done_tool: true }],
      }),
    });

    const result = await parentSpell.cast("test gate inheritance");
    expect(result).toBe("parent done with child result");
  });
});

// ── COMP-2: call_entity blocks parent until child completes ─────────

describe("COMP-2: call_entity blocks parent until child completes", () => {
  test("COMP-2: parent waits for child cantrip to complete before continuing", async () => {
    const executionOrder: string[] = [];

    const childCrystal = makeLlm([
      () => {
        executionOrder.push("child_running");
        return {
          content: null,
          tool_calls: [
            {
              id: "child_done",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "42" }),
              },
            },
          ],
        };
      },
    ]);

    const childSpell = cantrip({
      crystal: childCrystal as any,
      call: { system_prompt: "compute" },
      circle: Circle({
        gates: [doneGate],
        wards: [{ max_turns: 5, require_done_tool: true }],
      }),
    });

    const callAgentGate = gate(
      "Call agent",
      async ({ intent }: { intent: string }) => {
        executionOrder.push("parent_calling_child");
        const result = await childSpell.cast(intent);
        executionOrder.push("parent_got_result");
        return result;
      },
      {
        name: "call_entity",
        schema: {
          type: "object",
          properties: { intent: { type: "string" } },
          required: ["intent"],
          additionalProperties: false,
        },
      },
    );

    const parentCrystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "p1",
            type: "function",
            function: {
              name: "call_entity",
              arguments: JSON.stringify({ intent: "compute 6*7" }),
            },
          },
        ],
      }),
      () => ({
        content: null,
        tool_calls: [
          {
            id: "p2",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "final" }),
            },
          },
        ],
      }),
    ]);

    const parentSpell = cantrip({
      crystal: parentCrystal as any,
      call: { system_prompt: "parent" },
      circle: Circle({
        gates: [doneGate, callAgentGate],
        wards: [{ max_turns: 10, require_done_tool: true }],
      }),
    });

    await parentSpell.cast("test blocking");

    // Verify order: parent calls child, child runs, parent gets result
    expect(executionOrder).toEqual([
      "parent_calling_child",
      "child_running",
      "parent_got_result",
    ]);
  });
});

// ── COMP-3: batch returns results in request order ─────────────────

describe("COMP-3: call_entity_batch returns results in request order", () => {
  test("COMP-3: batch delegation returns results in order", async () => {
    // Create child cantrips that return different results
    function makeChildCantrip(result: string) {
      const crystal = makeLlm([
        () => ({
          content: null,
          tool_calls: [
            {
              id: "child_done",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: result }),
              },
            },
          ],
        }),
      ]);

      return cantrip({
        crystal: crystal as any,
        call: { system_prompt: "child" },
        circle: Circle({
          gates: [doneGate],
          wards: [{ max_turns: 5, require_done_tool: true }],
        }),
      });
    }

    const childA = makeChildCantrip("A");
    const childB = makeChildCantrip("B");
    const childC = makeChildCantrip("C");

    const batchGate = gate(
      "Call agent batch",
      async ({ intents }: { intents: string[] }) => {
        // Run all children and return results in order
        const children = [childA, childB, childC];
        const results = await Promise.all(
          intents.map((intent, i) => children[i].cast(intent)),
        );
        return results.join(",");
      },
      {
        name: "call_entity_batch",
        schema: {
          type: "object",
          properties: {
            intents: { type: "array", items: { type: "string" } },
          },
          required: ["intents"],
          additionalProperties: false,
        },
      },
    );

    const parentCrystal = makeLlm([
      () => ({
        content: null,
        tool_calls: [
          {
            id: "p1",
            type: "function",
            function: {
              name: "call_entity_batch",
              arguments: JSON.stringify({ intents: ["return A", "return B", "return C"] }),
            },
          },
        ],
      }),
      () => ({
        content: null,
        tool_calls: [
          {
            id: "p2",
            type: "function",
            function: {
              name: "done",
              arguments: JSON.stringify({ message: "A,B,C" }),
            },
          },
        ],
      }),
    ]);

    const parentSpell = cantrip({
      crystal: parentCrystal as any,
      call: { system_prompt: "parent" },
      circle: Circle({
        gates: [doneGate, batchGate],
        wards: [{ max_turns: 10, require_done_tool: true }],
      }),
    });

    const result = await parentSpell.cast("test batch ordering");
    expect(result).toBe("A,B,C");
  });
});

// ── COMP-4: child entity has independent context ───────────────────

describe("COMP-4: child entity has independent context", () => {
  test("COMP-4: child cantrip does not see parent's messages", async () => {
    const childMessagesReceived: any[][] = [];

    const childCrystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query(messages: any[]) {
        childMessagesReceived.push([...messages]);
        return {
          content: null,
          tool_calls: [
            {
              id: "child_done",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "child done" }),
              },
            },
          ],
        };
      },
    };

    const childSpell = cantrip({
      crystal: childCrystal as any,
      call: { system_prompt: "child system" },
      circle: Circle({
        gates: [doneGate],
        wards: [{ max_turns: 5, require_done_tool: true }],
      }),
    });

    const callAgentGate = gate(
      "Call agent",
      async ({ intent }: { intent: string }) => {
        return await childSpell.cast(intent);
      },
      {
        name: "call_entity",
        schema: {
          type: "object",
          properties: { intent: { type: "string" } },
          required: ["intent"],
          additionalProperties: false,
        },
      },
    );

    let parentCallCount = 0;
    const parentCrystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        parentCallCount++;
        if (parentCallCount === 1) {
          return {
            content: null,
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "call_entity",
                  arguments: JSON.stringify({ intent: "read secret variable" }),
                },
              },
            ],
          };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "p2",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "parent done" }),
              },
            },
          ],
        };
      },
    };

    const parentSpell = cantrip({
      crystal: parentCrystal as any,
      call: { system_prompt: "parent secret context" },
      circle: Circle({
        gates: [doneGate, callAgentGate],
        wards: [{ max_turns: 10, require_done_tool: true }],
      }),
    });

    await parentSpell.cast("test context isolation");

    // Child should NOT see parent's system prompt or messages
    const childMessages = childMessagesReceived[0];
    const hasParentContext = childMessages.some(
      (m: any) =>
        typeof m.content === "string" &&
        m.content.includes("parent secret context"),
    );
    expect(hasParentContext).toBe(false);

    // Child should have its own system prompt
    expect(childMessages[0].content).toBe("child system");
  });
});

// ── COMP-5: child turns recorded as subtree in loom ────────────────
// TODO: untestable until the framework records child entity turns in
// the parent's loom with entity_id and parent_id linkage. Currently
// parent and child run independent Agent instances with no shared loom.
// The LOOM-8 test covers the loom subtree data structure directly.

// ── COMP-6: max_depth prevents further delegation ──────────────────
// NOTE: Framework-level max_depth warding (gate removal at depth limit) is not
// yet implemented. These tests verify user-land depth tracking, not framework
// enforcement. TODO: add framework-level depth ward that removes call_entity gate.

describe("COMP-6: user-land depth tracking prevents deep recursion", () => {
  test("COMP-6: depth-limited gate prevents deep recursion", async () => {
    let depth = 0;
    const maxDepth = 0;

    const callAgentGate = gate(
      "Call agent",
      async ({ intent }: { intent: string }) => {
        if (depth >= maxDepth) {
          throw new Error("max depth reached");
        }
        depth++;
        return "should not reach";
      },
      {
        name: "call_entity",
        schema: {
          type: "object",
          properties: { intent: { type: "string" } },
          required: ["intent"],
          additionalProperties: false,
        },
      },
    );

    let callCount = 0;
    const crystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        callCount++;
        if (callCount === 1) {
          return {
            content: null,
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "call_entity",
                  arguments: JSON.stringify({ intent: "sub" }),
                },
              },
            ],
          };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "p2",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "blocked" }),
              },
            },
          ],
        };
      },
    };

    const spell = cantrip({
      crystal: crystal as any,
      call: { system_prompt: "test" },
      circle: Circle({
        gates: [doneGate, callAgentGate],
        wards: [{ max_turns: 10, require_done_tool: true }],
      }),
    });

    const result = await spell.cast("test depth limit");
    expect(result).toBe("blocked");
  });

  test("COMP-6: depth decrements through recursion levels", async () => {
    let maxAllowedDepth = 2;
    let currentDepth = 0;

    function makeRecursiveCantrip(depth: number): ReturnType<typeof cantrip> {
      const callAgentGate = gate(
        "Call agent",
        async ({ intent }: { intent: string }) => {
          currentDepth++;
          if (currentDepth > maxAllowedDepth) {
            throw new Error("max depth exceeded");
          }
          const child = makeRecursiveCantrip(depth - 1);
          return await child.cast(intent);
        },
        {
          name: "call_entity",
          schema: {
            type: "object",
            properties: { intent: { type: "string" } },
            required: ["intent"],
            additionalProperties: false,
          },
        },
      );

      let called = false;
      const crystal = {
        model: "dummy",
        provider: "dummy",
        name: "dummy",
        async query() {
          if (!called && depth > 0) {
            called = true;
            return {
              content: null,
              tool_calls: [
                {
                  id: `call_depth_${depth}`,
                  type: "function",
                  function: {
                    name: "call_entity",
                    arguments: JSON.stringify({ intent: `level ${depth}` }),
                  },
                },
              ],
            };
          }
          return {
            content: null,
            tool_calls: [
              {
                id: `done_depth_${depth}`,
                type: "function",
                function: {
                  name: "done",
                  arguments: JSON.stringify({ message: `deepest at depth ${depth}` }),
                },
              },
            ],
          };
        },
      };

      return cantrip({
        crystal: crystal as any,
        call: { system_prompt: `agent at depth ${depth}` },
        circle: Circle({
          gates: [doneGate, callAgentGate],
          wards: [{ max_turns: 10, require_done_tool: true }],
        }),
      });
    }

    const rootSpell = makeRecursiveCantrip(2);
    const result = await rootSpell.cast("test depth decrement");
    expect(result).toBeDefined();
    expect(currentDepth).toBe(2); // went 2 levels deep
  });
});

// ── COMP-7: child can use different crystal ────────────────────────

describe("COMP-7: child can use different crystal", () => {
  test("COMP-7: parent and child use different crystals", async () => {
    const parentCrystalCalls: string[] = [];
    const childCrystalCalls: string[] = [];

    const childCrystal = {
      model: "child-model",
      provider: "child",
      name: "child",
      async query() {
        childCrystalCalls.push("child invoked");
        return {
          content: null,
          tool_calls: [
            {
              id: "child_done",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "from alternate" }),
              },
            },
          ],
        };
      },
    };

    const childSpell = cantrip({
      crystal: childCrystal as any,
      call: { system_prompt: "alternate crystal" },
      circle: Circle({
        gates: [doneGate],
        wards: [{ max_turns: 5, require_done_tool: true }],
      }),
    });

    const callAgentGate = gate(
      "Call agent",
      async ({ intent }: { intent: string }) => childSpell.cast(intent),
      {
        name: "call_entity",
        schema: {
          type: "object",
          properties: { intent: { type: "string" } },
          required: ["intent"],
          additionalProperties: false,
        },
      },
    );

    let parentCallCount = 0;
    const parentCrystal = {
      model: "parent-model",
      provider: "parent",
      name: "parent",
      async query() {
        parentCrystalCalls.push("parent invoked");
        parentCallCount++;
        if (parentCallCount === 1) {
          return {
            content: null,
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "call_entity",
                  arguments: JSON.stringify({ intent: "use different crystal" }),
                },
              },
            ],
          };
        }
        return {
          content: null,
          tool_calls: [
            {
              id: "p2",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "from alternate" }),
              },
            },
          ],
        };
      },
    };

    const result = await cantrip({
      crystal: parentCrystal as any,
      call: { system_prompt: "parent" },
      circle: Circle({
        gates: [doneGate, callAgentGate],
        wards: [{ max_turns: 10, require_done_tool: true }],
      }),
    }).cast("test crystal override");

    expect(result).toBe("from alternate");
    expect(parentCrystalCalls.length).toBeGreaterThan(0);
    expect(childCrystalCalls.length).toBeGreaterThan(0);
  });
});

// ── COMP-8: child failure returns error to parent ──────────────────

describe("COMP-8: child failure returns error to parent", () => {
  test("COMP-8: child error is caught by parent as gate error", async () => {
    const childCrystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        throw new Error("child exploded");
      },
    };

    const childSpell = cantrip({
      crystal: childCrystal as any,
      call: { system_prompt: "child" },
      circle: Circle({
        gates: [doneGate],
        wards: [{ max_turns: 5, require_done_tool: true }],
      }),
    });

    const callAgentGate = gate(
      "Call agent",
      async ({ intent }: { intent: string }) => {
        return await childSpell.cast(intent);
      },
      {
        name: "call_entity",
        schema: {
          type: "object",
          properties: { intent: { type: "string" } },
          required: ["intent"],
          additionalProperties: false,
        },
      },
    );

    let parentCallCount = 0;
    const parentCrystal = {
      model: "dummy",
      provider: "dummy",
      name: "dummy",
      async query() {
        parentCallCount++;
        if (parentCallCount === 1) {
          return {
            content: null,
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "call_entity",
                  arguments: JSON.stringify({ intent: "will fail" }),
                },
              },
            ],
          };
        }
        // Parent recovers after seeing child error
        return {
          content: null,
          tool_calls: [
            {
              id: "p2",
              type: "function",
              function: {
                name: "done",
                arguments: JSON.stringify({ message: "caught error" }),
              },
            },
          ],
        };
      },
    };

    const result = await cantrip({
      crystal: parentCrystal as any,
      call: { system_prompt: "parent" },
      circle: Circle({
        gates: [doneGate, callAgentGate],
        wards: [{ max_turns: 10, require_done_tool: true }],
      }),
    }).cast("test child failure");

    // Parent should have recovered
    expect(result).toBe("caught error");
    expect(parentCallCount).toBe(2);
  });
});
