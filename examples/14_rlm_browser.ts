/**
 * RLM with Browser Automation
 *
 * Combines the Recursive Language Model pattern with Taiko browser automation.
 * The agent can browse the web, interact with pages, and process results
 * using the full RLM toolkit (code execution, sub-agent delegation, etc.).
 *
 * Browser functions are available directly in the sandbox as blocking calls:
 *   goto("https://example.com")
 *   var btn = button("Submit");
 *   click(btn, near(text("Login")));
 *   var title = title();
 *
 * Selectors return opaque handles that can be composed with proximity
 * selectors and passed to action functions.
 *
 * Usage:
 *   bun run examples/14_rlm_browser.ts
 *   bun run examples/14_rlm_browser.ts --headed          # visible browser
 *   bun run examples/14_rlm_browser.ts --context data.json
 *   bun run examples/14_rlm_browser.ts --openai
 *   bun run examples/14_rlm_browser.ts --gemini
 */

import { createRlmAgent } from "../src/rlm/service";
import { runRepl } from "../src/agent/repl";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { ChatOpenAI } from "../src/llm/openai/chat";
import { ChatGoogle } from "../src/llm/google/chat";
import { BrowserContext } from "../src/tools/builtin/browser_context";
import {
  createRlmConsoleRenderer,
  patchStderrForRlm,
} from "../src/rlm/console";
import fs from "fs";

async function main() {
  const args = process.argv.slice(2);
  let contextPath = "";
  let useOpenAI = false;
  let useGemini = false;
  let headed = false;
  let verbose = false;
  const queryArgs: string[] = [];

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--context" && args[i + 1]) {
      contextPath = args[i + 1];
      i++;
    } else if (args[i] === "--openai") {
      useOpenAI = true;
    } else if (args[i] === "--gemini") {
      useGemini = true;
    } else if (args[i] === "--headed") {
      headed = true;
    } else if (args[i] === "--verbose" || args[i] === "-v") {
      verbose = true;
    } else if (!args[i].startsWith("-")) {
      queryArgs.push(args[i]);
    }
  }

  process.argv = [process.argv[0], process.argv[1], ...queryArgs];

  // Load external data (optional)
  let context: unknown = "No external data loaded.";
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
    console.error(`Loaded data from ${contextPath} (${size})`);
  } else if (contextPath) {
    console.error(`Data file not found: ${contextPath}`);
  }

  const llm = useGemini
    ? new ChatGoogle({
        model: process.env.GOOGLE_MODEL ?? "gemini-3-flash-preview",
      })
    : useOpenAI
      ? new ChatOpenAI({ model: process.env.OPENAI_MODEL ?? "gpt-5-mini" })
      : new ChatAnthropic({
          model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5",
        });

  // Launch browser
  console.error(`Launching ${headed ? "headed" : "headless"} browser...`);
  const browserContext = await BrowserContext.create({
    headless: !headed,
    profile: "full",
  });

  // Create RLM agent with browser
  const { agent, sandbox } = await createRlmAgent({
    llm,
    context,
    maxDepth: 1,
    browserContext,
  });

  // Activate colorized output
  patchStderrForRlm();
  const renderer = createRlmConsoleRenderer({ verbose });

  console.error("RLM browser agent ready.");

  await runRepl({
    agent,
    prompt: "browser \u203a ",
    verbose,
    renderer,
    greeting: [
      "RLM agent with browser automation.",
      "Browser functions are available in the sandbox: goto(), click(), button(), text(), etc.",
      "Ctrl+C to exit.",
    ].join("\n"),
    onClose: async () => {
      sandbox.dispose();
      await browserContext.dispose();
    },
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
