// ACP — Agent Control Protocol adapter for editor integration.
// Serves a cantrip over ACP so editors (VS Code, etc.) can interact with it.
// Uses JS medium with filesystem gates — one medium, gates cross in.

import "./env";
import {
  cantrip, Circle, ChatAnthropic, max_turns,
  serveCantripACP,
  SandboxContext, getSandboxContext, safeFsGates,
} from "../src";
import { js } from "../src/circle/medium/js";
import { getRlmSystemPrompt } from "../src/circle/recipe/rlm_prompt";
import { analyzeContext } from "../src/circle/recipe/rlm";

export async function main() {
  serveCantripACP(async ({ params }) => {
    const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
    const ctx = await SandboxContext.create(params.cwd);

    const workspace = {
      working_dir: ctx.working_dir,
      description: "ACP coding agent with filesystem access.",
    };

    // ONE medium: JS sandbox. Filesystem gates cross in as host functions.
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
      call: { system_prompt: `${systemPrompt}\n\nCoding assistant. Working dir: ${ctx.working_dir}` },
      circle,
      dependency_overrides: new Map([[getSandboxContext, () => ctx]]),
    }).invoke();

    return {
      entity,
      onClose: async () => {
        await circle.dispose?.();
      },
    };
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
