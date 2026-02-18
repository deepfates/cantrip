// Filesystem gates — read, write, edit, glob, and bash.
// Uses cantrip().invoke() + runRepl for interactive use.

import "./env";
import {
  cantrip, runRepl, Circle, ChatAnthropic, max_turns,
  SandboxContext, getSandboxContext, unsafeFsGates, done,
} from "../src";

async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
  const ctx = await SandboxContext.create();

  const circle = Circle({
    gates: [...unsafeFsGates, done],
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
    greeting: "Filesystem agent ready. Ctrl+C to exit.",
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
