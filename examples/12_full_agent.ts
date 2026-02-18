// Full agent — filesystem, JavaScript, and browser gates in one circle.
// Uses cantrip().invoke() + runRepl for interactive use with all capabilities.

import "./env";
import {
  cantrip, runRepl, Circle, ChatAnthropic, max_turns,
  SandboxContext, getSandboxContext, unsafeFsGates,
  js, js_run, JsContext, getJsContext,
  browser, BrowserContext, getBrowserContext,
  done,
} from "../src";

async function main() {
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
  const fsCtx = await SandboxContext.create();
  const jsCtx = await JsContext.create();
  let browserCtx: BrowserContext | null = null;

  const lazyGetBrowser = async () => {
    if (!browserCtx) {
      console.log("[Browser] Launching...");
      browserCtx = await BrowserContext.create({ headless: true, profile: "full" });
    }
    return browserCtx;
  };

  const circle = Circle({
    gates: [...unsafeFsGates, js, js_run, browser, done],
    wards: [max_turns(200)],
  });

  const entity = cantrip({
    crystal,
    call: { system_prompt: `You have filesystem, JavaScript, and browser gates.
Working dir: ${fsCtx.working_dir}
Call done when finished.` },
    circle,
    dependency_overrides: new Map<any, any>([
      [getSandboxContext, () => fsCtx],
      [getJsContext, () => jsCtx],
      [getBrowserContext, lazyGetBrowser],
    ]),
  }).invoke();

  await runRepl({
    entity,
    greeting: "Full agent ready. Ctrl+C to exit.",
    onClose: async () => {
      jsCtx.dispose();
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
