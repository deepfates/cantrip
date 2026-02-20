// Tests JS medium context isolation, recursive delegation (llm_query/llm_batch),
// metadata loop, and token aggregation using cantrip() composition.
import { describe, expect, test, afterEach } from "bun:test";
import { JsAsyncContext } from "../../../src/circle/medium/js/async_context";
import type { BaseChatModel } from "../../../src/crystal/crystal";
import type { AnyMessage } from "../../../src/crystal/messages";
import type { ChatInvokeCompletion } from "../../../src/crystal/views";
import { cantrip } from "../../../src/cantrip/cantrip";
import { Circle } from "../../../src/circle/circle";
import { js, getJsMediumSandbox } from "../../../src/circle/medium/js";
import { max_turns, require_done } from "../../../src/circle/ward";
import { call_entity, call_entity_batch, spawnBinding, type SpawnFn } from "../../../src/circle/gate/builtin/call_entity_gate";
import { done_for_medium } from "../../../src/circle/gate/builtin/done";
import type { Entity } from "../../../src/cantrip/entity";
import { UsageTracker } from "../../../src/crystal/tokens";

/**
 * Local helper for tests.
 * Uses cantrip() + Circle() + js() composition.
 *
 * Provides a custom spawn that gives children their own JS medium circles,
 * so children get sandboxes with `context`, `submit_answer()`, etc.
 */
async function createTestAgent(opts: {
  llm: BaseChatModel;
  context: unknown;
  maxDepth?: number;
  depth?: number;
  /** Shared usage tracker for aggregating tokens across parent + children. */
  usage_tracker?: UsageTracker;
}): Promise<{ entity: Entity; sandbox: JsAsyncContext }> {
  const depth = opts.depth ?? 0;
  const maxDepth = opts.maxDepth ?? 2;
  const usage_tracker = opts.usage_tracker ?? new UsageTracker();

  const medium = js({ state: { context: opts.context } });
  const gates = [done_for_medium()];
  const entityGate = call_entity({ max_depth: maxDepth, depth, parent_context: opts.context });
  if (entityGate) gates.push(entityGate);
  const batchGate = call_entity_batch({ max_depth: maxDepth, depth, parent_context: opts.context });
  if (batchGate) gates.push(batchGate);

  const circle = Circle({ medium, gates, wards: [max_turns(20), require_done()] });

  // Build a spawn function that recursively creates children with their own sandboxes.
  // Children get full circles, not just plain LLM calls.
  const childDepth = depth + 1;
  const richSpawn: SpawnFn = async (query: string, context: unknown): Promise<string> => {
    if (childDepth >= maxDepth) {
      // At max depth: plain LLM call (no sandbox) — this is the fallback behavior
      const res = await opts.llm.query([
        { role: "user", content: query },
      ]);
      if (res.usage) {
        usage_tracker.add(opts.llm.model, res.usage);
      }
      return res.content ?? "";
    }
    // Below max depth: child gets its own circle with sandbox, shares the usage tracker
    const child = await createTestAgent({
      llm: opts.llm,
      context,
      maxDepth,
      depth: childDepth,
      usage_tracker,
    });
    try {
      return await child.entity.cast(query);
    } finally {
      child.sandbox.dispose();
    }
  };

  // Override the spawnBinding so the Entity uses our rich spawn instead of the default
  const overrides = new Map<any, any>();
  overrides.set(spawnBinding, (): SpawnFn => richSpawn);

  const spell = cantrip({
    crystal: opts.llm,
    call: "Explore the context using code. Use submit_answer() to provide your final answer.",
    circle,
    dependency_overrides: overrides,
    usage_tracker,
  });
  const entity = spell.invoke();

  // Init medium AFTER entity so spawnBinding is available
  await medium.init(gates, entity.dependency_overrides);
  const sandbox = getJsMediumSandbox(medium)!;

  return { entity, sandbox };
}

/**
 * Mock LLM that can simulate JS entity behaviors.
 * Responses are sequential by default, or can be determined by inspecting messages.
 */
class MockEntityLlm implements BaseChatModel {
  model = "mock-entity";
  provider = "mock";
  name = "mock-entity";
  private callCount = 0;

  constructor(
    private responses: ((messages: AnyMessage[]) => ChatInvokeCompletion)[],
  ) {}

  async query(messages: AnyMessage[]): Promise<ChatInvokeCompletion> {
    const idx = Math.min(this.callCount, this.responses.length - 1);
    const responseFn = this.responses[idx];
    this.callCount++;
    const res = responseFn(messages);
    return {
      ...res,
      usage: res.usage ?? {
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
      },
    };
  }
}

describe("JS Entity Integration", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("Metadata Loop: Model sees metadata, not full content in history", async () => {
    const hugeContext = "A".repeat(100000);

    const mockLlm = new MockEntityLlm([
      () => ({
        content: "Step 1",
        tool_calls: [
          {
            id: "c1",
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({ code: "context.length" }),
            },
          },
        ],
      }),
      (messages) => {
        const toolMsg = messages.find((m) => m.role === "tool") as any;
        const toolContent = toolMsg?.content || "";
        // Metadata check: history should contain the length string but not the massive "A" sequence
        if (toolContent.includes("100000") && !toolContent.includes("AAAAA")) {
          return {
            content: "Success",
            tool_calls: [
              {
                id: "c2",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "submit_answer('History is clean')",
                  }),
                },
              },
            ],
          };
        }
        return { content: "Failed: " + toolContent, tool_calls: [] };
      },
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: hugeContext,
    });
    activeSandbox = sandbox;
    const result = await entity.cast("test");
    expect(result).toBe("History is clean");
  });

  test("Recursion: llm_query spawns a child agent and returns result", async () => {
    const mockLlm = new MockEntityLlm([
      (msgs) => {
        const lastMsg = msgs[msgs.length - 1];
        if (lastMsg.role === "user" && lastMsg.content === "Start") {
          return {
            content: "Parent",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var res = llm_query('Get Secret'); submit_answer(res);",
                  }),
                },
              },
            ],
          };
        }
        if (lastMsg.role === "user" && lastMsg.content === "Get Secret") {
          // Child gets its own sandbox — it can access context and call submit_answer()
          return {
            content: "Child Result",
            tool_calls: [
              {
                id: "child1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "submit_answer(context.secret);",
                  }),
                },
              },
            ],
          };
        }
        return { content: "Error", tool_calls: [] };
      },
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: { secret: "password123" },
      maxDepth: 2,
    });
    activeSandbox = sandbox;

    const result = await entity.cast("Start");
    expect(result).toBe("password123");

    // Verify token aggregation: Parent tracker should see both its tokens and child's
    const usage = await entity.get_usage();
    // 1 parent call + 1 child call = 2 calls * 10 prompt tokens = 20
    expect(usage.total_prompt_tokens).toBeGreaterThanOrEqual(20);
  });

  test("Recursion Depth Limit: llm_query falls back to plain LLM call at max depth", async () => {
    // maxDepth=1: depth 0 has sandbox + llm_query. depth 1 child also has sandbox + llm_query.
    // But depth 1's llm_query spawns at depth 2 which >= maxDepth, so it falls back to a plain LLM call.
    // Chain: L0 sandbox → calls llm_query('L1') → L1 child gets sandbox → calls llm_query('L2')
    //        → L2 at max depth → plain LLM call → returns content directly
    const mockLlm = new MockEntityLlm([
      () => ({
        content: "Level 0",
        tool_calls: [
          {
            id: "L0",
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: "var res = llm_query('L1'); submit_answer(res);",
              }),
            },
          },
        ],
      }),
      // L1 child gets its own sandbox at depth=1, calls llm_query('L2')
      () => ({
        content: "Level 1",
        tool_calls: [
          {
            id: "L1",
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: "var res = llm_query('L2'); submit_answer(res);",
              }),
            },
          },
        ],
      }),
      // L2 at max depth: plain LLM call, no sandbox — just returns content
      () => ({
        content: "Max Depth Reached",
        tool_calls: [],
      }),
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: "data",
      maxDepth: 2,
    });
    activeSandbox = sandbox;

    const result = await entity.cast("Start");
    expect(result).toBe("Max Depth Reached");
  });

  test("submit_answer: Correctly extracts and stringifies complex objects", async () => {
    const mockLlm = new MockEntityLlm([
      () => ({
        content: "Calculating...",
        tool_calls: [
          {
            id: "c1",
            type: "function",
            function: {
              name: "js",
              arguments: JSON.stringify({
                code: "var obj = { a: 1, b: [2, 3] }; submit_answer(obj);",
              }),
            },
          },
        ],
      }),
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: {},
    });
    activeSandbox = sandbox;

    const result = await entity.cast("Start");
    const parsed = JSON.parse(result);
    expect(parsed.a).toBe(1);
    expect(parsed.b).toEqual([2, 3]);
  });

  test("Context Isolation: Child cannot modify parent context", async () => {
    const mockLlm = new MockEntityLlm([
      (msgs) => {
        const lastMsg = msgs[msgs.length - 1];
        if (lastMsg.content === "Start") {
          return {
            content: "Parent",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "llm_query('Change'); submit_answer(context.data);",
                  }),
                },
              },
            ],
          };
        }
        if (lastMsg.content === "Change") {
          // Child gets its own sandbox — it can mutate its own context
          return {
            content: "Child",
            tool_calls: [
              {
                id: "c1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "context.data = 'changed'; submit_answer('ok');",
                  }),
                },
              },
            ],
          };
        }
        return { content: "Error", tool_calls: [] };
      },
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: { data: "original" },
      maxDepth: 2,
    });
    activeSandbox = sandbox;

    const result = await entity.cast("Start");
    // Parent's context should still be 'original' despite child's attempt to mutate
    expect(result).toBe("original");
  });

  test("Batching: llm_batch executes multiple sub-queries in parallel", async () => {
    const mockLlm = new MockEntityLlm([
      (msgs) => {
        const lastMsg = msgs[msgs.length - 1];
        if (lastMsg.role === "user" && lastMsg.content === "Start") {
          return {
            content: "Parent batching",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var results = llm_batch([{query:'t', context:'a'}, {query:'t', context:'b'}]); submit_answer(results.join(', '));",
                  }),
                },
              },
            ],
          };
        }
        // Children get their own sandboxes — they call submit_answer with their context
        return {
          content: "Child",
          tool_calls: [
            {
              id: "c_" + Math.random(),
              type: "function",
              function: {
                name: "js",
                arguments: JSON.stringify({
                  code: "submit_answer('Result for ' + context)",
                }),
              },
            },
          ],
        };
      },
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: "parent",
      maxDepth: 2,
    });
    activeSandbox = sandbox;

    const result = await entity.cast("Start");
    expect(result).toBe("Result for a, Result for b");

    // Verify token aggregation for batch
    const usage = await entity.get_usage();
    // 1 parent call + 2 parallel child calls = 3 calls * 10 prompt tokens = 30
    expect(usage.total_prompt_tokens).toBeGreaterThanOrEqual(30);
  });
});
