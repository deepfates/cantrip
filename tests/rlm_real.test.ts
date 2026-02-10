import { describe, expect, test } from "bun:test";
import { createRlmAgent } from "../src/rlm/service";
import { ChatOpenAI } from "../src/llm/openai/chat";
import { loadEnv } from "./helpers/env";

loadEnv();

const hasKey = Boolean(process.env.OPENAI_API_KEY);
const it = hasKey ? test : test.skip;

// Per the RLM paper: "For GPT-5 experiments, we use GPT-5-mini for recursive LMs and GPT-5 for the root LM"
const modelName =
  process.env.OPENAI_RLM_MODEL ?? process.env.OPENAI_MODEL ?? "gpt-5-mini";

describe("rlm: real integration", () => {
  it("solves a context-isolated needle search", async () => {
    const llm = new ChatOpenAI({ model: modelName });

    // Construct a large context (~50k chars) that should remain isolated in the sandbox
    const needle = ' SECRET_CODE: "X-99" ';
    const context =
      "Filler text. ".repeat(2000) + needle + "More filler. ".repeat(2000);

    const { agent, sandbox } = await createRlmAgent({
      llm,
      context,
      maxDepth: 0,
    });

    try {
      // The query is clean; the system prompt handles instructions for tools and termination.
      const result = await agent.query("What is the SECRET_CODE?");

      expect(result).toContain("X-99");

      // Verify Context Isolation: The full 50kb context should not be in the prompt history
      const historyJson = JSON.stringify(agent.history);

      // Prompt history should be small (metadata + model turns only)
      expect(historyJson.length).toBeLessThan(15000);
      // Ensure the actual filler text didn't leak in
      expect(historyJson).not.toContain("Filler text. ".repeat(50));
    } catch (e) {
      console.log(
        "Needle Test Failed. History:",
        JSON.stringify(agent.history, null, 2),
      );
      throw e;
    } finally {
      sandbox.dispose();
    }
  }, 90000);

  it("handles recursive delegation via llm_query", async () => {
    const llm = new ChatOpenAI({ model: modelName });

    const context = {
      data_points: [
        { type: "noise", val: 123 },
        { type: "signal", val: "The password is 'FLYING-FISH'" },
        { type: "noise", val: 456 },
      ],
    };

    const { agent, sandbox } = await createRlmAgent({
      llm,
      context,
      maxDepth: 1,
    });

    try {
      // Testing the model's ability to filter and delegate based on system prompt rules
      const result = await agent.query(
        "Extract the password from the signal item in the data_points.",
      );

      expect(result.toUpperCase()).toContain("FLYING-FISH");
    } catch (e) {
      console.log(
        "Recursion Test Failed. History:",
        JSON.stringify(agent.history, null, 2),
      );
      throw e;
    } finally {
      sandbox.dispose();
    }
  }, 120000);
});
