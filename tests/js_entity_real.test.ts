// Tests real LLM integration with JS medium sandbox (context isolation,
// recursive delegation) using cantrip() composition.
import { describe, expect, test } from "bun:test";
import { ChatOpenAI } from "../src/crystal/providers/openai/chat";
import { loadEnv } from "./helpers/env";
import { cantrip } from "../src/cantrip/cantrip";
import { Circle } from "../src/circle/circle";
import { js, getJsMediumSandbox } from "../src/circle/medium/js";
import { max_turns, require_done } from "../src/circle/ward";
import { call_entity, call_entity_batch } from "../src/circle/gate/builtin/call_entity_gate";
import { done_for_medium } from "../src/circle/gate/builtin/done";
import { JsAsyncContext } from "../src/circle/medium/js/async_context";
import type { BaseChatModel } from "../src/crystal/crystal";
import type { Entity } from "../src/cantrip/entity";

loadEnv();

const hasKey = Boolean(process.env.OPENAI_API_KEY);
const it = hasKey ? test : test.skip;

const modelName =
  process.env.OPENAI_MODEL ?? "gpt-5-mini";

async function createTestAgent(opts: {
  llm: BaseChatModel;
  context: unknown;
  maxDepth?: number;
}): Promise<{ entity: Entity; sandbox: JsAsyncContext }> {
  const medium = js({ state: { context: opts.context } });
  const gates = [done_for_medium()];
  const entityGate = call_entity({ max_depth: opts.maxDepth ?? 2, depth: 0, parent_context: opts.context });
  if (entityGate) gates.push(entityGate);
  const batchGate = call_entity_batch({ max_depth: opts.maxDepth ?? 2, depth: 0, parent_context: opts.context });
  if (batchGate) gates.push(batchGate);

  const circle = Circle({ medium, gates, wards: [max_turns(20), require_done()] });
  const spell = cantrip({
    crystal: opts.llm,
    call: "Explore the context using code. Use submit_answer() to provide your final answer.",
    circle,
  });
  const entity = spell.invoke();

  await medium.init(gates, entity.dependency_overrides);
  const sandbox = getJsMediumSandbox(medium)!;

  return { entity, sandbox };
}

describe("JS entity: real integration", () => {
  it("solves a context-isolated needle search", async () => {
    const llm = new ChatOpenAI({ model: modelName });

    // Construct a large context (~50k chars) that should remain isolated in the sandbox
    const needle = ' SECRET_CODE: "X-99" ';
    const context =
      "Filler text. ".repeat(2000) + needle + "More filler. ".repeat(2000);

    const { entity, sandbox } = await createTestAgent({
      llm,
      context,
      maxDepth: 0,
    });

    try {
      const result = await entity.cast("What is the SECRET_CODE?");

      expect(result).toContain("X-99");

      // Verify Context Isolation: The full 50kb context should not be in the prompt history
      const historyJson = JSON.stringify(entity.history);
      expect(historyJson.length).toBeLessThan(15000);
      expect(historyJson).not.toContain("Filler text. ".repeat(50));
    } catch (e) {
      console.log(
        "Needle Test Failed. History:",
        JSON.stringify(entity.history, null, 2),
      );
      throw e;
    } finally {
      sandbox.dispose();
    }
  }, 90000);

  it("explores structured context and extracts a value", async () => {
    const llm = new ChatOpenAI({ model: modelName });

    const context = {
      data_points: [
        { type: "noise", val: 123 },
        { type: "signal", val: "The password is 'FLYING-FISH'" },
        { type: "noise", val: 456 },
      ],
    };

    const { entity, sandbox } = await createTestAgent({
      llm,
      context,
      maxDepth: 0, // No recursion — data is small enough to explore directly
    });

    try {
      const result = await entity.cast(
        "Extract the password from the signal item in the data_points.",
      );

      expect(result.toUpperCase()).toContain("FLYING-FISH");
    } catch (e) {
      console.log(
        "Structured Context Test Failed. History:",
        JSON.stringify(entity.history, null, 2),
      );
      throw e;
    } finally {
      sandbox.dispose();
    }
  }, 120000);
});
