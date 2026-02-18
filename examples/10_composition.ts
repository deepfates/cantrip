// Composition — delegate work to sub-agents via RLM.
// createRlmAgent puts data outside the prompt; the entity explores via code.

import "./env";
import { createRlmAgent, ChatOpenAI } from "../src";

async function main() {
  const crystal = new ChatOpenAI({ model: "gpt-5-mini" });

  // Data stays outside the prompt window — injected into a QuickJS sandbox.
  const hugeContext = {
    documents: [
      { id: 1, type: "noise", content: "The weather is nice today." },
      { id: 2, type: "signal", content: "The secret password is: FLYING-FISH" },
      { id: 3, type: "noise", content: "Remember to buy milk." },
    ],
  };

  const { agent, sandbox } = await createRlmAgent({
    llm: crystal,
    context: hugeContext,
    maxDepth: 1, // one level of recursive sub-agent delegation
  });

  try {
    const answer = await agent.query("Find the secret password in the documents.");
    console.log("Answer:", answer);
  } finally {
    sandbox.dispose();
  }
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
