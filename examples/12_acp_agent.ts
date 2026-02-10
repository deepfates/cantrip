import "./env";
import { Agent } from "../src/agent/service";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import {
  SandboxContext,
  getSandboxContext,
  unsafeFsTools,
} from "../src/tools/builtin/fs";
import { browser } from "../src/tools/builtin/browser";
import {
  BrowserContext,
  getBrowserContext,
} from "../src/tools/builtin/browser_context";
import { done } from "../src/tools/builtin/default";
import { serveCantripACP } from "../src/acp";

serveCantripACP(async ({ params }) => {
  const ctx = await SandboxContext.create(params.cwd);
  
  // Lazy initialization of browser context (only created when first used)
  let browserCtx: BrowserContext | null = null;
  const lazyGetBrowser = async () => {
    if (!browserCtx) {
      browserCtx = await BrowserContext.create({
        headless: true,
        profile: "full",
      });
    }
    return browserCtx;
  };

  const agent = new Agent({
    llm: new ChatAnthropic({ model: "claude-sonnet-4-5" }),
    tools: [...unsafeFsTools, browser, done],
    system_prompt: `You are a helpful coding assistant. Working directory: ${ctx.working_dir}`,
    dependency_overrides: new Map([
      [getSandboxContext, () => ctx],
      [getBrowserContext, lazyGetBrowser],
    ]),
  });

  // Return a session handle with cleanup
  return {
    agent,
    onClose: async () => {
      if (browserCtx) {
        await browserCtx.dispose();
      }
    },
  };
});
