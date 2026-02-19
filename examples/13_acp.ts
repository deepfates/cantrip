// ACP — Agent Control Protocol adapter for editor integration.
// Serves a cantrip over ACP so editors (VS Code, etc.) can interact with it.

import "./env";
import {
  cantrip, Circle, ChatAnthropic, max_turns,
  serveCantripACP,
  SandboxContext, getSandboxContext, unsafeFsGates,
  browser, BrowserContext, getBrowserContext,
  done,
} from "../src";

export async function main() {
  serveCantripACP(async ({ params }) => {
    const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
    const ctx = await SandboxContext.create(params.cwd);

    let browserCtx: BrowserContext | null = null;
    const lazyGetBrowser = async () => {
      if (!browserCtx) {
        browserCtx = await BrowserContext.create({ headless: true, profile: "full" });
      }
      return browserCtx;
    };

    const circle = Circle({
      gates: [...unsafeFsGates, browser, done],
      wards: [max_turns(200)],
    });

    const entity = cantrip({
      crystal,
      call: { system_prompt: `Coding assistant. Working dir: ${ctx.working_dir}\nCall done when finished.` },
      circle,
      dependency_overrides: new Map([
        [getSandboxContext, () => ctx],
        [getBrowserContext, lazyGetBrowser],
      ]),
    }).invoke();

    return {
      entity,
      onClose: async () => {
        if (browserCtx) await browserCtx.dispose();
      },
    };
  });
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
