import readline from "readline";

import { Agent, TaskComplete } from "../src/agent/service";
import { createConsoleRenderer } from "../src/agent/console";
import { ChatOpenAI } from "../src/llm/openai/chat";
import { js } from "../src/tools/builtin/js";
import { js_run } from "../src/tools/builtin/js_run";
import { JsContext, getJsContext } from "../src/tools/builtin/js_context";
import { done } from "../src/tools/builtin/default";

export async function main() {
  const verbose = (() => {
    const value = process.env.VERBOSE?.toLowerCase();
    return value === "1" || value === "true" || value === "yes";
  })();

  // Initialize the persistent JS context for the 'js' tool
  console.log("[JS] Initializing WASM runtime...");
  const jsCtx = await JsContext.create();

  const agent = new Agent({
    llm: new ChatOpenAI({ model: "gpt-4o" }),
    tools: [js, js_run, done],
    system_prompt: `You are a Code Execution Agent.
You have two ways to run JavaScript:

1. 'js' tool:
   - Persistent state (variables survive between calls).
   - Good for building up complex logic step-by-step.
   - NO access to fetch or filesystem. Pure computation/logic only.

2. 'js_run' tool:
   - Fresh state every time (variables lost).
   - Use 'export default' to return a value.
   - Can access fetch() and virtual fs (depending on config, defaults enabled).

Use these tools to solve math problems, process data, or write algorithms.`,
    dependency_overrides: new Map([[getJsContext, () => jsCtx]]),
  });

  console.log(
    "JS Agent ready. Type a request (e.g., 'Calculate the 100th Fibonacci number').",
  );
  console.log("Ctrl+C to exit.");

  const renderer = createConsoleRenderer({ verbose });
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: "› ",
  });

  let pending = Promise.resolve();

  rl.on("line", (line) => {
    pending = pending.then(async () => {
      const task = line.trim();
      if (!task) {
        rl.prompt();
        return;
      }

      if (task === "/quit" || task === "/exit") {
        rl.close();
        return;
      }

      rl.pause();
      const state = renderer.createState();
      try {
        for await (const event of agent.query_stream(task)) {
          renderer.handle(event, state);
        }
      } catch (err: any) {
        if (err instanceof TaskComplete) {
          console.log(`\nCompleted: ${err.result}`);
        } else {
          console.error(`\nError: ${err.message}`);
        }
      }
      console.log("─");
      rl.resume();
      rl.prompt();
    });
  });

  rl.on("close", () => {
    console.log("Disposing runtime...");
    jsCtx.dispose();
    process.exit(0);
  });

  rl.prompt();
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
