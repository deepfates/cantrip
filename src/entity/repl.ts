import readline from "readline";

import { Agent } from "./service";
import type { Entity } from "../cantrip/entity";
import {
  createConsoleRenderer,
  type ConsoleRenderer,
  type ConsoleRendererOptions,
} from "./console";

/** Resolve a streamable source — Entity preferred, Agent for backward compat. */
function resolveStreamable(options: { agent?: Agent; entity?: Entity }): {
  stream: (task: string) => AsyncGenerator<any>;
} {
  if (options.entity) {
    return { stream: (task: string) => options.entity!.turn_stream(task) };
  }
  if (options.agent) {
    return { stream: (task: string) => options.agent!.query_stream(task) };
  }
  throw new Error("Either agent or entity is required");
}

export type ExecOptions = {
  agent?: Agent;
  entity?: Entity;
  task: string;
  verbose?: boolean;
  /** Custom renderer — overrides the default console renderer */
  renderer?: {
    createState: () => any;
    handle: (event: any, state: any) => void;
  };
};

/**
 * Run an agent once with a task and print the result to stdout.
 * Unix-friendly: no prompts, no decoration, just output.
 */
export async function exec(options: ExecOptions): Promise<void> {
  const { stream } = resolveStreamable(options);
  const { task } = options;
  const verbose = options.verbose ?? false;

  const renderer = options.renderer ?? createConsoleRenderer({ verbose });
  const state = renderer.createState();

  for await (const event of stream(task)) {
    renderer.handle(event, state);
  }
}

export type ReplOptions = {
  agent?: Agent;
  entity?: Entity;
  prompt?: string;
  verbose?: boolean;
  greeting?: string;
  onClose?: () => void | Promise<void>;
  /** Called after each turn completes */
  onTurn?: () => void | Promise<void>;
  /** Custom renderer — overrides the default console renderer */
  renderer?: {
    createState: () => any;
    handle: (event: any, state: any) => void;
  };
};

/**
 * Run an interactive REPL for the given agent.
 *
 * Handles three modes:
 * - CLI args: `bun run agent.ts "What is 2+2?"` runs once and exits
 * - Piped input: `echo "What is 2+2?" | bun run agent.ts` runs once and exits
 * - Interactive: opens a REPL prompt
 */
export async function runRepl(options: ReplOptions): Promise<void> {
  const { stream } = resolveStreamable(options);
  const { onClose, onTurn } = options;
  const prompt = options.prompt ?? "› ";
  const verbose =
    options.verbose ??
    (() => {
      const value = process.env.VERBOSE?.toLowerCase();
      return value === "1" || value === "true" || value === "yes";
    })();

  // CLI args: run once and exit
  const args = process.argv.slice(2);
  if (args.length > 0) {
    const task = args.join(" ");
    await exec({ ...options, task, verbose });
    if (onTurn) await onTurn();
    if (onClose) await onClose();
    return;
  }

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
    await exec({ ...options, task, verbose });
    if (onTurn) await onTurn();
    if (onClose) await onClose();
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
      for await (const event of stream(task)) {
        renderer.handle(event, state);
      }
      if (onTurn) await onTurn();
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

  const renderer = options.renderer ?? createConsoleRenderer({ verbose });
  rl.prompt();
}
