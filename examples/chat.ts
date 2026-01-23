import readline from "readline";

import { Agent } from "../src/agent/service";
import { createConsoleRenderer } from "../src/agent/console";
import { ChatOpenAI } from "../src/llm/openai/chat";
import { rawTool } from "../src/tools/raw";
import { TaskComplete } from "../src/agent/errors";

const think = rawTool(
  {
    name: "think",
    description:
      "Use this tool to think through a problem step by step. Record your reasoning, analyze tool outputs, or work through decisions before acting. Your thoughts are recorded in context but have no external effects.",
    parameters: {
      type: "object",
      properties: { thought: { type: "string" } },
      required: ["thought"],
      additionalProperties: false,
    },
  },
  async ({ thought }: { thought: string }) => thought,
);

const done = rawTool(
  {
    name: "done",
    description:
      "Signal that you've completed the task. Call this when you have a final answer.",
    parameters: {
      type: "object",
      properties: { result: { type: "string" } },
      required: ["result"],
      additionalProperties: false,
    },
  },
  async ({ result }: { result: string }) => {
    throw new TaskComplete(result);
  },
);

export async function main() {
  const verbose = (() => {
    const value = process.env.VERBOSE?.toLowerCase();
    return value === "1" || value === "true" || value === "yes";
  })();

  const agent = new Agent({
    llm: new ChatOpenAI({ model: "gpt-4o" }),
    tools: [think, done],
    require_done_tool: true,
  });

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
    const state = renderer.createState();
    for await (const event of agent.query_stream(task)) {
      renderer.handle(event, state);
    }
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
