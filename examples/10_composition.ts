// Composition — delegate work to sub-agents via RLM.
// The JS medium puts data outside the prompt; the entity explores via code.

import "./env";
import { cantrip, Circle, max_turns, require_done, ChatOpenAI } from "../src";
import { js } from "../src/circle/medium/js";
import { getRlmSystemPrompt } from "../src/circle/gate/builtin/call_entity_prompt";
import { analyzeContext } from "../src/circle/gate/builtin/call_entity";

// ── cantrip + JS medium ─────────────────────────────────────────────

export async function main() {
  const crystal = new ChatOpenAI({ model: "gpt-5-mini" });

  // Data stays outside the prompt window — injected into a QuickJS sandbox.
  const data = {
    documents: [
      { id: 1, type: "noise", content: "The weather is nice today." },
      { id: 2, type: "signal", content: "The secret password is: FLYING-FISH" },
      { id: 3, type: "noise", content: "Remember to buy milk." },
    ],
  };

  // Build a circle with a JS medium — the entity works inside a QuickJS sandbox.
  const circle = Circle({
    medium: js({ state: { context: data } }),
    wards: [max_turns(20), require_done()],
  });

  // Generate a system prompt that describes the sandbox environment.
  const metadata = analyzeContext(data);
  const systemPrompt = getRlmSystemPrompt({
    contextType: metadata.type,
    contextLength: metadata.length,
    contextPreview: metadata.preview,
    hasRecursion: false,
  });

  const spell = cantrip({
    crystal,
    call: { system_prompt: systemPrompt },
    circle,
  });

  try {
    const answer = await spell.cast("Find the secret password in the documents.");
    console.log("Answer:", answer);
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
