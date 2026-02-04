import { Agent } from "../src/agent/service";
import { runRepl } from "../src/agent/repl";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import {
  SandboxContext,
  getSandboxContext,
  unsafeFsTools,
} from "../src/tools/builtin/fs";
import { done } from "../src/tools/builtin/default";

export async function main() {
  const ctx = await SandboxContext.create();

  const agent = new Agent({
    llm: new ChatAnthropic({ model: "claude-sonnet-4-5" }),
    tools: [...unsafeFsTools, done],
    system_prompt: `Coding assistant. Working dir: ${ctx.working_dir}`,
    dependency_overrides: new Map([[getSandboxContext, () => ctx]]),
  });

  await runRepl({
    agent,
    greeting: "Filesystem agent ready. Ctrl+C to exit.",
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
