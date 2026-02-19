// Example 13: ACP — Agent Control Protocol adapter for editor integration.
// Serves a cantrip over ACP so editors (VS Code, etc.) can interact with it.
// Medium: conversation | LLM: No (server — starts an ACP server)

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
  console.log("--- Example 13: ACP Server ---");
  console.log("Serves a cantrip over the Agent Control Protocol.");
  console.log("Editors (VS Code, etc.) connect and interact with the entity.");

  serveCantripACP(async ({ params }) => {
    const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
    const ctx = await SandboxContext.create(params.cwd);

    const workspace = {
      working_dir: ctx.working_dir,
      description: "ACP coding agent with filesystem access.",
    };

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

  return "acp-server-started";
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
