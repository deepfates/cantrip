// Browser gate — headless browser control via Taiko.
// The browser context is lazily created on first use.

import "./env";
import {
  cantrip, runRepl, Circle, ChatAnthropic, max_turns,
  browser, BrowserContext, getBrowserContext, done,
} from "../src";

async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  let browserCtx: BrowserContext | null = null;
  const lazyGetBrowser = async () => {
    if (!browserCtx) {
      console.log("[Browser] Launching...");
      browserCtx = await BrowserContext.create({ headless: true, profile: "full" });
    }
    return browserCtx;
  };

  const circle = Circle({
    gates: [browser, done],
    wards: [max_turns(50)],
  });

  const entity = cantrip({
    crystal,
    call: { system_prompt: "You control a headless browser. Navigate, click, extract data. Call done when finished." },
    circle,
    dependency_overrides: new Map([[getBrowserContext, lazyGetBrowser]]),
  }).invoke();

  await runRepl({
    entity,
    greeting: "Browser agent ready. Ctrl+C to exit.",
    onClose: async () => {
      if (browserCtx) await browserCtx.dispose();
    },
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
