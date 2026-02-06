/**
 * RLM with Auto-Managed Conversation Memory
 *
 * This extends the RLM pattern to handle long conversations. Instead of
 * compacting or summarizing old messages (lossy), older turns are moved
 * to a searchable context that the agent can query when needed.
 *
 * The context object has two parts:
 * - context.data: External data you provide (optional)
 * - context.history: Older conversation messages (auto-managed)
 *
 * Usage:
 *   bun run examples/11_rlm_memory.ts                    # interactive chat
 *   bun run examples/11_rlm_memory.ts --context data.json # with external data
 *   bun run examples/11_rlm_memory.ts --window 3          # keep 3 turns active
 */

import { createRlmAgentWithMemory } from "../src/rlm/service";
import { runRepl } from "../src/agent/repl";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { ChatOpenAI } from "../src/llm/openai/chat";
import fs from "fs";

async function main() {
  const args = process.argv.slice(2);
  let contextPath = "";
  let useOpenAI = false;
  let verbose = false;
  let windowSize = 5; // Default: keep 5 turns in active prompt
  const queryArgs: string[] = [];

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--context" && args[i + 1]) {
      contextPath = args[i + 1];
      i++;
    } else if (args[i] === "--window" && args[i + 1]) {
      windowSize = parseInt(args[i + 1], 10);
      i++;
    } else if (args[i] === "--openai") {
      useOpenAI = true;
    } else if (args[i] === "--verbose" || args[i] === "-v") {
      verbose = true;
    } else if (!args[i].startsWith("-")) {
      queryArgs.push(args[i]);
    }
  }

  process.argv = [process.argv[0], process.argv[1], ...queryArgs];

  // Load external data (optional)
  let data: unknown = undefined;
  if (contextPath && fs.existsSync(contextPath)) {
    const raw = fs.readFileSync(contextPath, "utf-8");
    try {
      data = JSON.parse(raw);
    } catch {
      data = raw;
    }
    const size =
      typeof data === "string"
        ? `${data.length} chars`
        : `${JSON.stringify(data).length} chars`;
    console.error(`Loaded data from ${contextPath} (${size})`);
  } else if (contextPath) {
    console.error(`Data file not found: ${contextPath}`);
  }

  const llm = useOpenAI
    ? new ChatOpenAI({ model: process.env.OPENAI_MODEL ?? "gpt-5-mini" })
    : new ChatAnthropic({
        model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5",
      });

  // Create RLM agent with memory management
  const { agent, sandbox, manageMemory } = await createRlmAgentWithMemory({
    llm,
    data,
    windowSize,
    maxDepth: 1,
  });

  console.error(`Memory window: ${windowSize} turns (older messages move to context.history)`);

  await runRepl({
    agent,
    prompt: "memory › ",
    verbose,
    greeting: "RLM agent with memory ready. Older messages will be searchable via context.history.",
    onTurn: manageMemory,
    onClose: () => sandbox.dispose(),
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
