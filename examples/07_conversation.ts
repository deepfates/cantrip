// Conversation medium — the baseline.
// When no medium is specified, the circle uses "conversation" as its medium.
// The crystal sees gates as tool calls in natural language.
// This is the simplest circle: just gates + wards, no code sandbox.

import "./env";
import {
  cantrip, runRepl, Circle, ChatAnthropic, max_turns,
  SandboxContext, getSandboxContext, safeFsGates, done,
} from "../src";

export async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
  const ctx = await SandboxContext.create();

  // "conversation" is a medium — the default. No `medium:` parameter means
  // the entity works via natural language tool calls (the baseline).
  // Gates cross INTO the circle from outside (filesystem access here).
  const circle = Circle({
    // No medium: → conversation medium (tool-calling baseline)
    gates: [...safeFsGates, done],
    wards: [max_turns(100)],
  });

  const entity = cantrip({
    crystal,
    call: { system_prompt: `Coding assistant. Working dir: ${ctx.working_dir}\nCall done when finished.` },
    circle,
    dependency_overrides: new Map([[getSandboxContext, () => ctx]]),
  }).invoke();

  await runRepl({
    entity,
    greeting: "Filesystem agent ready (conversation medium). Ctrl+C to exit.",
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
