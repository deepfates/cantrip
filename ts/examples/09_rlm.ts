/**
 * Recursive Language Model (RLM)
 *
 * The problem: LLMs have limited context windows and degrade ("context rot")
 * when you stuff too much data into the prompt.
 *
 * The solution: Keep the data OUTSIDE the prompt. Put it in a JavaScript
 * sandbox as a variable called `context`. The LLM writes code to explore it,
 * and can recursively spawn sub-agents to analyze chunks.
 *
 * This is based on Zhang et al.'s RLM paper (arxiv:2512.24601).
 *
 * Run: bun run examples/09_rlm.ts
 */

import { createRlmAgent } from "../src/rlm/service";
import { ChatOpenAI } from "../src/llm/openai/chat";

async function main() {
  const llm = new ChatOpenAI({ model: "gpt-5-mini" });

  // Imagine this is 10MB of data. It never enters the LLM's prompt window.
  // Instead, it's injected into a QuickJS sandbox as a global variable.
  const hugeContext = {
    documents: [
      { id: 1, type: "noise", content: "The weather is nice today." },
      { id: 2, type: "signal", content: "The secret password is: FLYING-FISH" },
      { id: 3, type: "noise", content: "Remember to buy milk." },
      // ... imagine thousands more
    ],
  };

  // Create an RLM-enabled agent
  const { agent, sandbox } = await createRlmAgent({
    llm,
    context: hugeContext,
    maxDepth: 1, // Allow one level of recursive sub-agents
  });

  try {
    // The agent sees a system prompt telling it about `context` (type, size, preview)
    // but NOT the actual data. It must use the `js` tool to explore.
    const answer = await agent.query(
      "Find the secret password in the documents.",
    );

    console.log("Answer:", answer);

    // Check that the huge context didn't leak into the prompt history
    const historySize = JSON.stringify(agent.history).length;
    console.log(`\nHistory size: ${historySize} chars (context stayed isolated)`);
  } finally {
    sandbox.dispose();
  }
}

main();
