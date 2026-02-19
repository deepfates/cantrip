// Example 07: Conversation Medium
// When no medium is specified, the circle uses "conversation" (tool-calling baseline).
// The crystal sees gates as tool calls in natural language. This is a REPL.

import "./env";
import {
  cantrip, runRepl, Circle, ChatAnthropic, max_turns,
  SandboxContext, getSandboxContext, safeFsGates, done,
} from "../src";

export async function main() {
  console.log("=== Example 07: Conversation Medium ===");
  console.log("No medium: parameter means conversation medium (tool-calling baseline).");
  console.log("Gates cross INTO the circle from outside — filesystem access here.\n");

  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
  const ctx = await SandboxContext.create();

  const circle = Circle({
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

  return "repl-exited";
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
