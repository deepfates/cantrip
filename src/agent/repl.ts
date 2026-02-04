import readline from "readline";

import { Agent } from "./service";
import { createConsoleRenderer, type ConsoleRendererOptions } from "./console";

export type ReplOptions = {
  agent: Agent;
  prompt?: string;
  verbose?: boolean;
  greeting?: string;
  onClose?: () => void | Promise<void>;
};

/**
 * Run an interactive REPL for the given agent.
 *
 * Handles stdin (TTY or piped), streaming output, and cleanup.
 */
export async function runRepl(options: ReplOptions): Promise<void> {
  const { agent, onClose } = options;
  const prompt = options.prompt ?? "› ";
  const verbose = options.verbose ?? (() => {
    const value = process.env.VERBOSE?.toLowerCase();
    return value === "1" || value === "true" || value === "yes";
  })();

  const rendererOptions: ConsoleRendererOptions = { verbose };
  const renderer = createConsoleRenderer(rendererOptions);

  const isTty = Boolean(process.stdin.isTTY);

  // Piped input: read all, run once, exit
  if (!isTty) {
    let input = "";
    process.stdin.setEncoding("utf8");
    for await (const chunk of process.stdin) {
      input += chunk;
    }
    const task = input.trim();
    if (!task) return;
    const state = renderer.createState();
    for await (const event of agent.query_stream(task)) {
      renderer.handle(event, state);
    }
    return;
  }

  // Interactive TTY mode
  if (options.greeting) {
    console.log(options.greeting);
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt,
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
      for await (const event of agent.query_stream(task)) {
        renderer.handle(event, state);
      }
      console.log("─");
      rl.resume();
      rl.prompt();
    });
  });

  rl.on("close", async () => {
    if (onClose) {
      await onClose();
    }
    process.exit(0);
  });

  rl.prompt();
}
