// Example 09: Browser Medium
// The entity works inside a Taiko browser session. It writes Taiko code.
// ONE medium per circle — the medium REPLACES conversation.

import "./env";
import { cantrip, Circle, ChatAnthropic, max_turns, require_done } from "../src";
import { browser } from "../src/circle/medium/browser";

export async function main() {
  console.log("=== Example 09: Browser Medium ===");
  console.log("The browser medium gives the entity a headless browser to work in.");
  console.log("The entity writes Taiko code to navigate, click, and extract data.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

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
    console.log('Asking: "Go to example.com and return the page title."');
    const answer = await spell.cast("Go to https://example.com and return the page title.");
    console.log(`Answer: ${answer}`);
    console.log("\nThe entity used browser automation to get the answer.");
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
