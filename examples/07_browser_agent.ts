import { Agent } from "../src/agent/service";
import { runRepl } from "../src/agent/repl";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import { browser } from "../src/tools/builtin/browser";
import {
  BrowserContext,
  getBrowserContext,
} from "../src/tools/builtin/browser_context";
import { done } from "../src/tools/builtin/default";

export async function main() {
  let browserCtx: BrowserContext | null = null;

  const lazyGetBrowser = async () => {
    if (!browserCtx) {
      console.log("[Browser] Launching headless browser...");
      browserCtx = await BrowserContext.create({
        headless: true,
        profile: "full",
      });
    }
    return browserCtx;
  };

  const agent = new Agent({
    llm: new ChatAnthropic({ model: "claude-sonnet-4-5" }),
    tools: [browser, done],
    system_prompt: `You are a web browsing agent. Use the 'browser' tool to control a headless browser via Taiko commands.

Common commands:
- await goto('url')
- return await currentURL()
- await click('text')
- await write('text', into(textBox('label')))
- return await text('selector').text()

Always return values if you need to see them.

When you complete the task, call the done tool with your findings. Be efficient.`,
    dependency_overrides: new Map([[getBrowserContext, lazyGetBrowser]]),
  });

  await runRepl({
    agent,
    greeting: "Browser agent ready. Ctrl+C to exit.",
    onClose: async () => {
      if (browserCtx) {
        console.log("Closing browser...");
        await browserCtx.dispose();
      }
    },
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
