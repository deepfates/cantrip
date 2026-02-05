/**
 * An implementation of the Recursive Language Model (RLM).
 */

import { Agent } from "../src/agent/service";
import { runRepl } from "../src/agent/repl";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { js } from "../src/tools/builtin/js";
import { JsContext, getJsContext } from "../src/tools/builtin/js_context";
import { done } from "../src/tools/builtin/default";

export async function main() {
  // Initialize contexts
  const jsCtx = await JsContext.create();

  const agent = new Agent({
    llm: new ChatAnthropic({ model: "claude-sonnet-4-5" }),
    tools: [
      js, // persistent JS REPL
      done, // signal completion
    ],
    system_prompt: `You are an agent with access to:

**JavaScript tool**
- js: persistent REPL, variables survive between calls, no network/fs

`,
    dependency_overrides: new Map<any, any>([[getJsContext, () => jsCtx]]),
  });

  await runRepl({
    agent,
    greeting: "Full agent ready. Ctrl+C to exit.",
    onClose: async () => {
      jsCtx.dispose();
    },
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
