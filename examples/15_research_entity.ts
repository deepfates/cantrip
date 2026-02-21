// Example 15: Research entity — the full-package capstone.
// ACP server + jsBrowser medium + recursive children + memory management.
// Medium: jsBrowser (JS sandbox + browser automation) | LLM: Yes | Recursion: Yes
//
// Composed from primitives — calls cantrip() directly.
// Multi-provider support via CLI flags: --openai, --gemini, --headed, --memory N.

import "./env";
import {
  cantrip,
  Circle,
  Loom,
  MemoryStorage,
  max_turns,
  require_done,
  call_entity_gate,
  call_entity_batch_gate,
  serveCantripACP,
  createAcpProgressCallback,
  BrowserContext,
  getBrowserContext,
  progressBinding,
  ChatAnthropic,
  ChatOpenAI,
  ChatGoogle,
  jsBrowserMedium,
  type BaseChatModel,
} from "../src";

// ── CLI args ──────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const headed = args.includes("--headed");
const useOpenai = args.includes("--openai");
const useGemini = args.includes("--gemini");
const memoryIdx = args.indexOf("--memory");
const memoryWindow = memoryIdx >= 0 ? parseInt(args[memoryIdx + 1], 10) : 0;

function pickCrystal(): BaseChatModel {
  if (useOpenai) return new ChatOpenAI({ model: "gpt-5-mini" });
  if (useGemini) return new ChatGoogle({ model: "gemini-3-flash-prevew" });
  return new ChatAnthropic({ model: "claude-sonnet-4-5" });
}

// ── ACP server ────────────────────────────────────────────────────────

export async function main() {
  console.log("--- Example 15: Research Entity (ACP) ---");
  console.log(
    `Provider: ${useOpenai ? "OpenAI" : useGemini ? "Gemini" : "Anthropic"}`,
  );
  console.log(`Browser: ${headed ? "headed" : "headless"}`);
  if (memoryWindow > 0) console.log(`Memory window: ${memoryWindow} messages`);

  serveCantripACP(async ({ params, sessionId, connection }) => {
    const crystal = pickCrystal();

    // Launch browser
    const browserContext = await BrowserContext.create({
      headless: !headed,
      profile: "full",
    });

    // Build gates — call_entity for recursive children, call_entity_batch for parallelism
    const entityGate = call_entity_gate({ max_depth: 2, depth: 0 });
    const batchGate = call_entity_batch_gate({ max_depth: 2, depth: 0 });
    const gates = [entityGate, batchGate].filter(Boolean) as any[];

    // Circle: jsBrowser medium + recursive gates + wards
    const circle = Circle({
      medium: jsBrowserMedium({ browserContext }),
      gates,
      wards: [max_turns(200), require_done()],
    });

    // Progress → ACP plan updates
    const onProgress = createAcpProgressCallback(sessionId, connection);
    const depOverrides = new Map<any, any>([
      [getBrowserContext, () => browserContext],
      [progressBinding, () => onProgress],
    ]);

    // Shared loom captures parent + child turns
    const loom = new Loom(new MemoryStorage());

    // The entity auto-prepends capability docs from the circle.
    const spell = cantrip({
      crystal,
      call:
        "Research entity with browser automation and recursive delegation. " +
        "Use code to explore data, browse the web, and delegate sub-intents via call_entity. " +
        "Use submit_answer() when done.",
      circle,
      loom,
      dependency_overrides: depOverrides,
    });

    const entity = spell.invoke();

    // Memory management: sliding window on entity history
    const onTurn =
      memoryWindow > 0
        ? () => {
            const history = entity.history;
            if (history.length > memoryWindow) {
              entity.load_history(history.slice(-memoryWindow));
            }
          }
        : undefined;

    return {
      entity,
      onTurn,
      onClose: async () => {
        await circle.dispose?.();
        await browserContext.dispose();
      },
    };
  });

  return "acp-server-started";
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
