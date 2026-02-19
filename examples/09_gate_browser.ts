// Browser medium — a Taiko browser session that the entity works inside.
// The entity writes Taiko code; gates are projected as available commands.
// ONE medium per circle. The medium REPLACES conversation.

import "./env";
import { cantrip, Circle, ChatAnthropic, max_turns, require_done } from "../src";
import { browser } from "../src/circle/medium/browser";

export async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  // The browser medium: entity works IN a Taiko browser session.
  // Gates (like submit_answer) are projected as callable functions inside it.
  const circle = Circle({
    medium: browser({ headless: true, profile: "full" }),
    wards: [max_turns(50), require_done()],
  });

  const spell = cantrip({
    crystal,
    call: {
      system_prompt: "You control a headless browser via Taiko. Navigate, click, extract data. Use submit_answer(value) to return your final result.",
    },
    circle,
  });

  try {
    const answer = await spell.cast("Go to https://example.com and return the page title.");
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
