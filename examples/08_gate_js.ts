// JavaScript gates — persistent REPL (js) and fresh sandbox (js_run).
// Two flavors: js keeps state between calls, js_run starts fresh each time.

import "./env";
import {
  cantrip, runRepl, Circle, ChatAnthropic, max_turns,
  js, js_run, JsContext, getJsContext, done,
} from "../src";

export async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
  const jsCtx = await JsContext.create();

  const circle = Circle({
    gates: [js, js_run, done],
    wards: [max_turns(100)],
  });

  const entity = cantrip({
    crystal,
    call: { system_prompt: `You have two JavaScript gates:
- js: persistent REPL, variables survive between calls
- js_run: fresh sandbox each call, has fetch/virtual fs, use 'export default' to return
Call done when finished.` },
    circle,
    dependency_overrides: new Map([[getJsContext, () => jsCtx]]),
  }).invoke();

  await runRepl({
    entity,
    greeting: "JavaScript agent ready. Ctrl+C to exit.",
    onClose: () => jsCtx.dispose(),
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
