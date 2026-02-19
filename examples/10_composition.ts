// Example 10: Composition — nested entities.
// The JS medium puts data outside the prompt; the entity explores via code.
// Medium: js | LLM: Yes

import "./env";
import { cantrip, Circle, max_turns, require_done, ChatOpenAI } from "../src";
import { js } from "../src/circle/medium/js";
import { getRlmSystemPrompt } from "../src/circle/recipe/rlm_prompt";
import { analyzeContext } from "../src/circle/recipe/rlm";

export async function main() {
  console.log("--- Example 10: Composition ---");
  console.log("Data stays outside the prompt window — injected into a QuickJS sandbox.");
  console.log("The entity writes code to search through it.");

  const crystal = new ChatOpenAI({ model: "gpt-5-mini" });

  const data = {
    documents: [
      { id: 1, type: "noise", content: "The weather is nice today." },
      { id: 2, type: "signal", content: "The secret password is: FLYING-FISH" },
      { id: 3, type: "noise", content: "Remember to buy milk." },
    ],
  };

  const circle = Circle({
    medium: js({ state: { context: data } }),
    wards: [max_turns(20), require_done()],
  });

  const metadata = analyzeContext(data);
  const systemPrompt = getRlmSystemPrompt({
    contextType: metadata.type,
    contextLength: metadata.length,
    contextPreview: metadata.preview,
  });

  const spell = cantrip({
    crystal,
    call: { system_prompt: systemPrompt },
    circle,
  });

  try {
    console.log('Asking: "Find the secret password in the documents."');
    const answer = await spell.cast("Find the secret password in the documents.");
    console.log("Answer:", answer);
    console.log("Done. The entity searched the data via code, not by seeing it in the prompt.");
    return answer;
  } finally {
    await circle.dispose?.();
  }
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
