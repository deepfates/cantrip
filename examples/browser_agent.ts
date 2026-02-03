import readline from "readline";

import { Agent, TaskComplete } from "../src/agent/service";
import { createConsoleRenderer } from "../src/agent/console";
import { ChatOpenAI } from "../src/llm/openai/chat";
import {
  browser,
  browser_interactive,
  browser_readonly,
} from "../src/tools/examples/browser";
import {
  BrowserContext,
  getBrowserContext,
  getBrowserContextInteractive,
  getBrowserContextReadonly,
} from "../src/tools/examples/browser_context";
import { done } from "../src/tools/examples/default";

function createLazyBrowserContext(
  profile: "full" | "interactive" | "readonly",
) {
  let ctxPromise: Promise<BrowserContext> | null = null;
  let ctx: BrowserContext | null = null;

  const getCtx = async () => {
    if (!ctxPromise) {
      console.log(`[Browser] Launching headless browser (${profile})...`);
      ctxPromise = BrowserContext.create({ headless: true, profile }).then(
        (created) => {
          ctx = created;
          return created;
        },
      );
    }
    return ctxPromise;
  };

  const dispose = async () => {
    if (ctxPromise) {
      await ctxPromise;
    }
    await ctx?.dispose();
  };

  return { getCtx, dispose };
}

export async function main() {
  const verbose = (() => {
    const value = process.env.VERBOSE?.toLowerCase();
    return value === "1" || value === "true" || value === "yes";
  })();

  // We create lazy contexts for different profiles if we want to expose different tools.
  // For this example, we'll just expose the full browser tool.
  const fullBrowser = createLazyBrowserContext("full");

  const agent = new Agent({
    llm: new ChatOpenAI({ model: "gpt-4o" }),
    tools: [browser, done],
    system_prompt: `You are a web surfing agent.
You can navigate the web, interact with pages, and extract information.
Use the 'browser' tool to control the browser using Taiko commands.
Common commands:
- await goto('url')
- return await currentURL()
- await click('text')
- await write('text', into(textBox('label')))
- return await text('content').text()

Always return values from the browser tool if you need to see them.`,
    dependency_overrides: new Map([
      [getBrowserContext, fullBrowser.getCtx],
      // If we used the other tools, we'd map them here too
      [getBrowserContextInteractive, fullBrowser.getCtx],
      [getBrowserContextReadonly, fullBrowser.getCtx],
    ]),
  });

  console.log("Browser Agent ready. Type a request (e.g., 'Go to google.com and search for cantrip agents').");
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

  rl.on("close", async () => {
    console.log("Closing browser...");
    await fullBrowser.dispose();
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
