/**
 * This example shows how to swap between different LLM providers.
 * All providers implement the same interface, so you can switch
 * by just changing the import and constructor.
 */

import { Agent, TaskComplete } from "../src/agent/service";
import { tool } from "../src/tools/decorator";

// Pick one:
import { ChatAnthropic } from "../src/llm/anthropic/chat";
// import { ChatOpenAI } from "../src/llm/openai/chat";
// import { ChatGoogle } from "../src/llm/google/chat";
// import { ChatOpenRouter } from "../src/llm/openrouter/chat";
// import { ChatLMStudio } from "../src/llm/lmstudio/chat";

const add = tool(
  "Add two numbers",
  async ({ a, b }: { a: number; b: number }) => a + b,
  { name: "add", params: { a: "number", b: "number" } },
);

const done = tool(
  "Signal task completion",
  async ({ message }: { message: string }) => {
    throw new TaskComplete(message);
  },
  { name: "done", params: { message: "string" } },
);

export async function main() {
  // Anthropic (Claude)
  // Requires: ANTHROPIC_API_KEY
  const llm = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  // OpenAI
  // Requires: OPENAI_API_KEY
  // const llm = new ChatOpenAI({ model: "gpt-5.2" });

  // Google (Gemini)
  // Requires: GOOGLE_API_KEY
  // const llm = new ChatGoogle({ model: "gemini-3-flash-preview" });

  // OpenRouter (access many models via one API)
  // Requires: OPENROUTER_API_KEY
  // const llm = new ChatOpenRouter({ model: "anthropic/claude-sonnet-4-5" });

  // LM Studio (local models)
  // No API key needed, runs at http://localhost:1234/v1 by default
  // const llm = new ChatLMStudio({ model: "gpt-oss-20b" }); // or whatever

  const agent = new Agent({
    llm,
    tools: [add, done],
  });

  const result = await agent.query("What is 2 + 3?");
  console.log(result);
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
