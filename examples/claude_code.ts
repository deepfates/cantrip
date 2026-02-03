import readline from "readline";

import { Agent } from "../src/agent/service";
import { createConsoleRenderer } from "../src/agent/console";
import { ChatOpenAI } from "../src/llm/openai/chat";
import {
  SandboxContext,
  getSandboxContext,
  unsafeFsTools,
} from "../src/tools/builtins/fs";
import { done } from "../src/tools/builtins/default";

export async function main() {
  const ctx = await SandboxContext.create();
  const verbose = (() => {
    const value = process.env.VERBOSE?.toLowerCase();
    return value === "1" || value === "true" || value === "yes";
  })();

  const agent = new Agent({
    llm: new ChatOpenAI({ model: "gpt-4o" }),
    tools: [...unsafeFsTools, done],
    system_prompt: `Coding assistant. Working dir: ${ctx.working_dir}`,
    dependency_overrides: new Map([[getSandboxContext, () => ctx]]),
  });

  console.log("Agent ready. Ctrl+C to exit.");

  const isTty = Boolean(process.stdin.isTTY);

  const renderer = createConsoleRenderer({ verbose });

  if (!isTty) {
    let input = "";
    process.stdin.setEncoding("utf8");
    for await (const chunk of process.stdin) {
      input += chunk;
    }
    const task = input.trim();
    if (!task) return;
    const text = (await agent.query(task)).replace(/\s+$/, "");
    if (text) console.log(text);
    return;
  }

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
      rl.pause();
      const state = renderer.createState();
      for await (const event of agent.query_stream(task)) {
        renderer.handle(event, state);
      }
      console.log("─");
      rl.resume();
      rl.prompt();
    });
  });

  rl.prompt();
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
