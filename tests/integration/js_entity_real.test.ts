// Tests real LLM integration with JS medium sandbox (context isolation,
// data extraction) using cantrip() composition.
import { describe, expect, test } from "bun:test";
import { ChatOpenAI } from "../../src/crystal/providers/openai/chat";
import { loadEnv } from "../helpers/env";
import { cantrip } from "../../src/cantrip/cantrip";
import { Circle } from "../../src/circle/circle";
import { js } from "../../src/circle/medium/js";
import { max_turns, require_done } from "../../src/circle/ward";
import { done_for_medium } from "../../src/circle/gate/builtin/done";


loadEnv();

const hasKey = Boolean(process.env.OPENAI_API_KEY);
const it = hasKey ? test : test.skip;

const modelName =
  process.env.OPENAI_MODEL ?? "gpt-5-mini";

const CALL_STRATEGY = [
  "Explore the context using code. Always inspect data with console.log() before answering.",
  "For strings: use .indexOf() or .match() to search, then .slice() to extract.",
  "When you have the answer, call submit_answer() with your result.",
].join("\n");

function createTestCircle(context: unknown) {
  const medium = js({ state: { context } });
  const gates = [done_for_medium()];
  return Circle({ medium, gates, wards: [max_turns(20), require_done()] });
}

function createLlm(reasoning_effort: "low" | "medium" | "high" = "medium") {
  // gpt-5-mini is a reasoning model — needs adequate reasoning_effort for tool-use tasks.
  // Default "low" causes it to skip data inspection and hallucinate field names.
  return new ChatOpenAI({ model: modelName, reasoning_effort });
}

describe("JS entity: real integration", () => {
  it("solves a context-isolated needle search", async () => {
    const llm = createLlm();

    // Construct a large context (~50k chars) that should remain isolated in the sandbox.
    // The needle must be an opaque token so the model can't partially extract it.
    const needle = "The passphrase is ZYGOMORPHIC.";
    const context =
      "Filler text. ".repeat(2000) + needle + " More filler. ".repeat(2000);

    const circle = createTestCircle(context);
    const spell = cantrip({ crystal: llm, call: CALL_STRATEGY, circle });

    try {
      const result = await spell.cast(
        "The variable `context` contains a large string. " +
        "Somewhere in that string is a sentence with a passphrase. " +
        "Find and return the exact passphrase."
      );
      expect(result).toContain("ZYGOMORPHIC");
    } finally {
      await circle.dispose?.();
    }
  }, 180000);

  it("explores structured context and extracts a value", async () => {
    const llm = createLlm();

    const context = {
      data_points: [
        { type: "noise", val: 123 },
        { type: "signal", val: "The password is 'FLYING-FISH'" },
        { type: "noise", val: 456 },
      ],
    };

    const circle = createTestCircle(context);
    const spell = cantrip({ crystal: llm, call: CALL_STRATEGY, circle });

    try {
      const result = await spell.cast(
        "Extract the password from the signal item in the data_points.",
      );
      expect(result.toUpperCase()).toContain("FLYING-FISH");
    } finally {
      await circle.dispose?.();
    }
  }, 180000);
});
