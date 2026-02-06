/**
 * RLM Interactive REPL
 *
 * Load a file as context and query it with the RLM pattern.
 *
 * Usage:
 *   bun run examples/10_rlm.ts --context data.json "What's in the data?"
 *   bun run examples/10_rlm.ts --context corpus.txt  # interactive mode
 *   echo "Find the secret" | bun run examples/10_rlm.ts --context data.json
 */

import { createRlmAgent } from "../src/rlm/service";
import { runRepl } from "../src/agent/repl";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { ChatOpenAI } from "../src/llm/openai/chat";
import fs from "fs";

async function main() {
  // Parse flags before runRepl consumes args
  const args = process.argv.slice(2);
  let contextPath = "";
  let useOpenAI = false;
  let verbose = false;
  const queryArgs: string[] = [];

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--context" && args[i + 1]) {
      contextPath = args[i + 1];
      i++; // skip next
    } else if (args[i] === "--openai") {
      useOpenAI = true;
    } else if (args[i] === "--verbose" || args[i] === "-v") {
      verbose = true;
    } else if (!args[i].startsWith("-")) {
      // Only pass through non-flag args as query
      queryArgs.push(args[i]);
    }
  }

  // Restore query args for runRepl to use
  process.argv = [process.argv[0], process.argv[1], ...queryArgs];

  // Load context from file
  let context: unknown =
    "No context loaded. Use --context <path> to provide data.";
  if (contextPath && fs.existsSync(contextPath)) {
    const raw = fs.readFileSync(contextPath, "utf-8");
    try {
      context = JSON.parse(raw);
    } catch {
      context = raw;
    }
    const size =
      typeof context === "string"
        ? `${context.length} chars`
        : `${JSON.stringify(context).length} chars`;
    console.error(`Loaded context from ${contextPath} (${size})`);
  } else if (contextPath) {
    console.error(`Context not found: ${contextPath}`);
  }

  // Initialize LLM
  const llm = useOpenAI
    ? new ChatOpenAI({ model: process.env.OPENAI_MODEL ?? "gpt-5-mini" })
    : new ChatAnthropic({
        model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5",
      });

  // Create RLM agent
  const { agent, sandbox } = await createRlmAgent({
    llm,
    context,
    maxDepth: 1,
  });

  // Run with standard REPL behavior
  await runRepl({
    agent,
    prompt: "rlm › ",
    verbose,
    greeting: "RLM agent ready. The context is loaded in the sandbox.",
    onClose: () => sandbox.dispose(),
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
