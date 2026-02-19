// Full agent — JS medium with filesystem gates.
// ONE medium per circle. The JS medium gives the entity a code sandbox;
// filesystem gates cross INTO it as host functions (read_file, write_file, etc.).

import "./env";
import {
  cantrip, runRepl, Circle, ChatAnthropic, max_turns,
  SandboxContext, getSandboxContext, safeFsGates,
} from "../src";
import { js } from "../src/circle/medium/js";
import { getRlmSystemPrompt } from "../src/circle/recipe/rlm_prompt";
import { analyzeContext } from "../src/circle/recipe/rlm";

export async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
  const fsCtx = await SandboxContext.create();

  // Data for the sandbox — the entity can explore it with code.
  const workspace = {
    working_dir: fsCtx.working_dir,
    description: "A coding workspace with filesystem access via host functions.",
  };

  // ONE medium: JS sandbox. Gates (filesystem ops) are projected as host functions.
  // The entity writes JS code that can call read_file(), write_file(), etc.
  const circle = Circle({
    medium: js({ state: { context: workspace } }),
    gates: [...safeFsGates],
    wards: [max_turns(200)],
  });

  const metadata = analyzeContext(workspace);
  const systemPrompt = getRlmSystemPrompt({
    contextType: metadata.type,
    contextLength: metadata.length,
    contextPreview: metadata.preview,
    hasRecursion: false,
  });

  const entity = cantrip({
    crystal,
    call: { system_prompt: `${systemPrompt}\n\nYou also have filesystem host functions: read_file, write_file, glob, bash.\nWorking dir: ${fsCtx.working_dir}` },
    circle,
    dependency_overrides: new Map([[getSandboxContext, () => fsCtx]]),
  }).invoke();

  await runRepl({
    entity,
    greeting: "Full agent ready (JS medium + filesystem gates). Ctrl+C to exit.",
    onClose: async () => {
      await circle.dispose?.();
    },
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
