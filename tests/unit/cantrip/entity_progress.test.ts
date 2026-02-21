// Tests progress event callbacks for sub-agent spawning and batching
// using cantrip() composition.
import { describe, expect, test, afterEach } from "bun:test";
import { JsAsyncContext } from "../../../src/circle/medium/js/async_context";
import type { BaseChatModel } from "../../../src/crystal/crystal";
import type { AnyMessage } from "../../../src/crystal/messages";
import type { ChatInvokeCompletion } from "../../../src/crystal/views";
import type { ProgressEvent, ProgressCallback } from "../../../src/entity/progress";
import { cantrip } from "../../../src/cantrip/cantrip";
import { Circle } from "../../../src/circle/circle";
import { js, getJsMediumSandbox } from "../../../src/circle/medium/js";
import { max_turns, require_done } from "../../../src/circle/ward";
import { call_entity, call_entity_batch, progressBinding } from "../../../src/circle/gate/builtin/call_entity_gate";
import { done_for_medium } from "../../../src/circle/gate/builtin/done";
import type { Entity } from "../../../src/cantrip/entity";

/**
 * Local helper for progress tests.
 */
async function createTestAgent(opts: {
  llm: BaseChatModel;
  context: unknown;
  maxDepth?: number;
  onProgress?: ProgressCallback;
}): Promise<{ entity: Entity; sandbox: JsAsyncContext }> {
  const medium = js({ state: { context: opts.context } });
  const gates = [done_for_medium()];
  const entityGate = call_entity({ max_depth: opts.maxDepth ?? 2, depth: 0, parent_context: opts.context });
  if (entityGate) gates.push(entityGate);
  const batchGate = call_entity_batch({ max_depth: opts.maxDepth ?? 2, depth: 0, parent_context: opts.context });
  if (batchGate) gates.push(batchGate);

  const depOverrides = new Map<any, any>();
  if (opts.onProgress) {
    depOverrides.set(progressBinding, () => opts.onProgress);
  }

  const circle = Circle({ medium, gates, wards: [max_turns(20), require_done()] });
  const spell = cantrip({
    crystal: opts.llm,
    call: "Explore the context using code. Use submit_answer() to provide your final answer.",
    circle,
    dependency_overrides: depOverrides.size > 0 ? depOverrides : null,
  });
  const entity = spell.invoke();

  // Merge entity's auto-populated bindings with user-provided overrides
  const mergedOverrides = new Map<any, any>(entity.dependency_overrides instanceof Map ? entity.dependency_overrides : []);
  for (const [k, v] of depOverrides) mergedOverrides.set(k, v);
  await medium.init(gates, mergedOverrides);
  const sandbox = getJsMediumSandbox(medium)!;

  return { entity, sandbox };
}

class MockLlm implements BaseChatModel {
  model = "mock";
  provider = "mock";
  name = "mock";
  private callCount = 0;

  constructor(
    private responses: ((messages: AnyMessage[]) => ChatInvokeCompletion)[],
  ) {}

  async query(messages: AnyMessage[]): Promise<ChatInvokeCompletion> {
    const idx = Math.min(this.callCount, this.responses.length - 1);
    this.callCount++;
    const res = this.responses[idx](messages);
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

describe("Entity progress events", () => {
  let activeSandbox: JsAsyncContext | null = null;

  afterEach(() => {
    if (activeSandbox) {
      activeSandbox.dispose();
      activeSandbox = null;
    }
  });

  test("llm_query emits sub_entity_start and sub_entity_end", async () => {
    const events: ProgressEvent[] = [];

    const mockLlm = new MockLlm([
      (msgs) => {
        const last = msgs[msgs.length - 1];
        if (last.content === "Start") {
          return {
            content: "Delegating",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var r = llm_query('child task'); submit_answer(r);",
                  }),
                },
              },
            ],
          };
        }
        if (last.content === "child task") {
          return {
            content: "Child",
            tool_calls: [
              {
                id: "c1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "submit_answer('done');",
                  }),
                },
              },
            ],
          };
        }
        return { content: "?", tool_calls: [] };
      },
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: {},
      maxDepth: 1,
      onProgress: (e) => events.push(e),
    });
    activeSandbox = sandbox;

    await entity.cast("Start");

    const starts = events.filter((e) => e.type === "sub_entity_start");
    const ends = events.filter((e) => e.type === "sub_entity_end");

    expect(starts).toHaveLength(1);
    expect(starts[0].depth).toBe(1);
    expect((starts[0] as any).query).toBe("child task");

    expect(ends).toHaveLength(1);
    expect(ends[0].depth).toBe(1);
  });

  test("llm_batch emits batch_start, batch_item, and batch_end", async () => {
    const events: ProgressEvent[] = [];

    const mockLlm = new MockLlm([
      (msgs) => {
        const last = msgs[msgs.length - 1];
        if (last.role === "user" && last.content === "Start") {
          return {
            content: "Batching",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var r = llm_batch([{query:'q1'}, {query:'q2'}]); submit_answer(r.join(','));",
                  }),
                },
              },
            ],
          };
        }
        return {
          content: "Child",
          tool_calls: [
            {
              id: "c" + Math.random(),
              type: "function",
              function: {
                name: "js",
                arguments: JSON.stringify({
                  code: "submit_answer('ok');",
                }),
              },
            },
          ],
        };
      },
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: {},
      maxDepth: 1,
      onProgress: (e) => events.push(e),
    });
    activeSandbox = sandbox;

    await entity.cast("Start");

    const batchStarts = events.filter((e) => e.type === "batch_start");
    const batchItems = events.filter((e) => e.type === "batch_item");
    const batchEnds = events.filter((e) => e.type === "batch_end");

    expect(batchStarts).toHaveLength(1);
    expect((batchStarts[0] as any).count).toBe(2);

    expect(batchItems).toHaveLength(2);
    expect((batchItems[0] as any).index).toBe(0);
    expect((batchItems[0] as any).total).toBe(2);
    expect((batchItems[0] as any).query).toBe("q1");
    expect((batchItems[1] as any).index).toBe(1);
    expect((batchItems[1] as any).query).toBe("q2");

    expect(batchEnds).toHaveLength(1);
  });

  test("llm_query works without onProgress callback (defaults to null)", async () => {
    const mockLlm = new MockLlm([
      (msgs) => {
        const last = msgs[msgs.length - 1];
        if (last.content === "Go") {
          return {
            content: "Delegating",
            tool_calls: [
              {
                id: "p1",
                type: "function",
                function: {
                  name: "js",
                  arguments: JSON.stringify({
                    code: "var r = llm_query('sub'); submit_answer(r);",
                  }),
                },
              },
            ],
          };
        }
        // Default spawn creates a real child cantrip with done gate.
        // Child has require_done_tool (inherited from parent wards via OR semantics),
        // so it needs a done tool call to terminate properly.
        const content = typeof last.content === "string" ? last.content : "";
        if (content.includes("sub")) {
          return {
            content: "child result",
            tool_calls: [
              {
                id: "done1",
                type: "function" as const,
                function: {
                  name: "done",
                  arguments: JSON.stringify({ message: "child result" }),
                },
              },
            ],
          };
        }
        return { content: "?", tool_calls: [] };
      },
    ]);

    const { entity, sandbox } = await createTestAgent({
      llm: mockLlm,
      context: {},
      maxDepth: 1,
      // No onProgress — progressBinding defaults to null, no crash
    });
    activeSandbox = sandbox;

    const result = await entity.cast("Go");
    expect(result).toBe("child result");
  });
});
