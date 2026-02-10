/**
 * RLM Browser Agent over ACP
 *
 * Combines RLM with browser automation over ACP.
 * The agent can browse the web, interact with pages, and use the full RLM
 * toolkit (code execution, sub-agent delegation) via your ACP-enabled editor.
 *
 * Optional memory management: Older conversation turns are moved to a 
 * searchable sandbox context, keeping the active prompt window small.
 *
 * Browser functions are available directly in the sandbox as blocking calls:
 *   goto("https://example.com")
 *   var btn = button("Submit");
 *   click(btn, near(text("Login")));
 *   var pageTitle = title();
 *
 * RLM functions:
 *   llm_query("analyze this data", someSubset)  // delegate to sub-agent
 *   submit_answer("result")  // return final answer
 *
 * Configure your ACP-enabled editor to launch:
 *   bun run examples/15_acp_rlm_browser.ts
 *   bun run examples/15_acp_rlm_browser.ts --headed  # visible browser
 *   bun run examples/15_acp_rlm_browser.ts --memory 5  # sliding window with 5 turn history
 *
 * Example VS Code settings.json:
 * {
 *   "acp.agents": [{
 *     "name": "cantrip-browser",
 *     "command": "bun",
 *     "args": ["run", "examples/15_acp_rlm_browser.ts", "--headed", "--memory", "5"],
 *     "cwd": "${workspaceFolder}"
 *   }]
 * }
 */

import "./env";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { createRlmAgent, createRlmAgentWithMemory } from "../src/rlm/service";
import { serveCantripACP, createAcpProgressCallback } from "../src/acp";
import { BrowserContext } from "../src/tools/builtin/browser_context";

// Parse command line arguments
const args = process.argv.slice(2);
let headed = false;
let windowSize: number | null = null;

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--headed") {
    headed = true;
  } else if (args[i] === "--memory" && args[i + 1]) {
    windowSize = parseInt(args[i + 1], 10);
    i++;
  }
}

serveCantripACP(async ({ params, sessionId, connection }) => {
  const llm = new ChatAnthropic({
    model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5",
  });

  const onProgress = createAcpProgressCallback(sessionId, connection);

  // Launch browser
  console.error(`Launching ${headed ? "headed" : "headless"} browser...`);
  const browserContext = await BrowserContext.create({
    headless: !headed,
    profile: "full",
  });

  // Create RLM agent with or without memory management
  if (windowSize !== null && windowSize > 0) {
    console.error(`Using memory window of ${windowSize} turns`);
    const { agent, sandbox, manageMemory } = await createRlmAgentWithMemory({
      llm,
      windowSize,
      maxDepth: 1,
      browserContext,
      onProgress,
    });

    return {
      agent,
      onTurn: manageMemory,
      onClose: async () => {
        sandbox.dispose();
        await browserContext.dispose();
      },
    };
  } else {
    console.error("No memory window (full history retained)");
    const { agent, sandbox } = await createRlmAgent({
      llm,
      context: { note: "No external data loaded. Use browser to gather information." },
      maxDepth: 1,
      browserContext,
      onProgress,
    });

    return {
      agent,
      onClose: async () => {
        sandbox.dispose();
        await browserContext.dispose();
      },
    };
  }
});
