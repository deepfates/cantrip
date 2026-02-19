// JS medium — a QuickJS sandbox that the entity works inside.
// The entity writes JavaScript code; gates are projected as host functions.
// ONE medium per circle. The medium REPLACES conversation.

import "./env";
import { cantrip, Circle, ChatAnthropic, max_turns, require_done } from "../src";
import { js } from "../src/circle/medium/js";
import { getRlmSystemPrompt } from "../src/circle/recipe/rlm_prompt";
import { analyzeContext } from "../src/circle/recipe/rlm";

export async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  // Data injected into the sandbox — available as globals to the entity's code.
  const data = {
    items: [
      { name: "alpha", value: 10 },
      { name: "beta", value: 25 },
      { name: "gamma", value: 7 },
    ],
  };

  // The JS medium: entity works IN a QuickJS sandbox.
  // Gates (like submit_answer) are projected as callable functions inside it.
  const circle = Circle({
    medium: js({ state: { context: data } }),
    wards: [max_turns(20), require_done()],
  });

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
    const answer = await spell.cast("Which item has the highest value? Return its name.");
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
