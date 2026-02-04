/**
 * A full-featured agent combining filesystem, JavaScript, and browser tools.
 *
 * This is what a "real" agent might look like. It can:
 * - Read, write, and edit files
 * - Run shell commands
 * - Execute JavaScript in a persistent REPL or sandboxed environment
 * - Browse the web with a headless browser
 *
 * Customize this to fit your use case, or use it as a reference
 * for building your own agent.
 */

import { Agent } from "../src/agent/service";
import { runRepl } from "../src/agent/repl";
import { ChatAnthropic } from "../src/llm/anthropic/chat";
import {
  SandboxContext,
  getSandboxContext,
  unsafeFsTools,
} from "../src/tools/builtin/fs";
import { js } from "../src/tools/builtin/js";
import { js_run } from "../src/tools/builtin/js_run";
import { JsContext, getJsContext } from "../src/tools/builtin/js_context";
import { browser } from "../src/tools/builtin/browser";
import {
  BrowserContext,
  getBrowserContext,
} from "../src/tools/builtin/browser_context";
import { done } from "../src/tools/builtin/default";

export async function main() {
  // Initialize contexts
  const fsCtx = await SandboxContext.create();
  const jsCtx = await JsContext.create();
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
    tools: [
      ...unsafeFsTools, // read, write, edit, glob, bash
      js, // persistent JS REPL
      js_run, // sandboxed JS execution
      browser, // headless browser
      done, // signal completion
    ],
    system_prompt: `You are an agent with access to:

**Filesystem tools** (working dir: ${fsCtx.working_dir})
- read, write, edit, glob, bash

**JavaScript tools**
- js: persistent REPL, variables survive between calls, no network/fs
- js_run: fresh sandbox each call, has fetch and virtual fs, use 'export default' to return

**Browser tool**
- browser: control a headless browser via Taiko commands

Use the right tool for each task. Prefer simpler tools when they suffice.`,
    dependency_overrides: new Map([
      [getSandboxContext, () => fsCtx],
      [getJsContext, () => jsCtx],
      [getBrowserContext, lazyGetBrowser],
    ]),
  });

  await runRepl({
    agent,
    greeting: "Full agent ready. Ctrl+C to exit.",
    onClose: async () => {
      jsCtx.dispose();
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
