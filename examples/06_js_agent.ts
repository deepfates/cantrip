import { Agent } from "../src/agent/service";
import { runRepl } from "../src/agent/repl";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { js } from "../src/tools/builtin/js";
import { js_run } from "../src/tools/builtin/js_run";
import { JsContext, getJsContext } from "../src/tools/builtin/js_context";
import { done } from "../src/tools/builtin/default";

export async function main() {
  const jsCtx = await JsContext.create();

  const agent = new Agent({
    llm: new ChatAnthropic({ model: "claude-sonnet-4-5" }),
    tools: [js, js_run, done],
    system_prompt: `You are a code execution agent with two JavaScript tools:

1. 'js' - Persistent REPL. Variables survive between calls. No fetch or filesystem.
2. 'js_run' - Fresh sandbox each time. Use 'export default' to return values. Has fetch and virtual fs.

Use these to solve problems, run calculations, or process data.`,
    dependency_overrides: new Map([[getJsContext, () => jsCtx]]),
  });

  await runRepl({
    agent,
    greeting: "JS agent ready. Ctrl+C to exit.",
    onClose: () => jsCtx.dispose(),
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
