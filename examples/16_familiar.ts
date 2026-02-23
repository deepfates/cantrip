// Example 16: The Familiar — cantrip construction as medium physics.
// A long-running coordinator entity that creates and casts child cantrips from code.
// Medium: JS (with cantrip() + cast() + repo introspection) | LLM: Yes | Recursion: via cantrip/cast
//
// The Familiar doesn't have direct access to bash, browser, or filesystem.
// It constructs child cantrips with those capabilities and delegates to them.
// Repo introspection gates let it observe the codebase without acting on it.
// Loom is persisted to disk so the entity remembers across sessions.
//
// Three modes:
//   bun run examples/16_familiar.ts              → REPL (default)
//   bun run examples/16_familiar.ts "task"       → single-shot
//   bun run examples/16_familiar.ts --acp        → ACP server for editor integration

import "./env";
import { resolve } from "node:path";
import { mkdirSync } from "node:fs";
import {
  cantrip,
  Circle,
  ChatAnthropic,
  max_turns,
  require_done,
  repoGates,
  getRepoContextDepends,
  RepoContext,
  Loom,
  MemoryStorage,
  JsonlStorage,
  done,
  runRepl,
  cantripGates,
  serveCantripACP,
  createAcpProgressCallback,
  progressBinding,
} from "../src";
import { js } from "../src/circle/medium/js";
import { bash } from "../src/circle/medium/bash";
import { browser } from "../src/circle/medium/browser";
import type { CantripMediumConfig } from "../src/circle/gate/builtin/cantrip";

// ── CLI args ──────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const useAcp = args.includes("--acp");
const memoryIdx = args.indexOf("--memory");
const memoryWindow = memoryIdx >= 0 ? parseInt(args[memoryIdx + 1], 10) : 0;

// Positional arg = single-shot intent (skip flags and their values)
let positionalArg: string | undefined;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--memory") {
    i++;
    continue;
  }
  if (args[i].startsWith("--")) continue;
  positionalArg = args[i];
  break;
}

// ── Persistent loom ──────────────────────────────────────────────────

function createLoom(
  repoRoot: string,
  ephemeral = false,
): { loom: Loom; loomPath: string | null } {
  if (ephemeral) {
    return { loom: new Loom(new MemoryStorage()), loomPath: null };
  }
  const dir = resolve(repoRoot, ".cantrip");
  mkdirSync(dir, { recursive: true });
  const loomPath = resolve(dir, "loom.jsonl");
  return { loom: new Loom(new JsonlStorage(loomPath)), loomPath };
}

// ── System prompt ────────────────────────────────────────────────────

const SYSTEM_PROMPT = (repoRoot: string, loomPath: string | null) =>
  `You are the Familiar — the singular, long-running partner entity bound to the repository at ${repoRoot}.

You exist inside a JS medium. That means you write JavaScript code to do things, and
your code runs in a persistent runtime where variables stick around between turns.
You can't directly touch the shell, browser, or filesystem from here — but you can
observe the repo, and more importantly, you can create and cast child cantrips that
DO have those capabilities.

## Repo observation (read-only)

These functions let you look around without changing anything:

  repo_files(pattern?)     — list files matching a glob (e.g. "src/**/*.ts")
  repo_read(path, opts?)   — read file contents (offset/limit for windowing)
  repo_git_log(n?)         — recent commits
  repo_git_status()        — working tree status
  repo_git_diff(path?)     — staged + unstaged diff

## Creating and casting cantrips

This is your primary power. The API here is the same cantrip API that application
developers use to create you — you're writing the same code they write, just from
the inside. The only difference is that you refer to crystals and mediums by name
(strings like "haiku" or "bash") rather than by object reference, because you're
on the other side of a serialization boundary.

Two functions:

  cantrip(config) → handle
  cast(handle, intent) → result string

To take action in the world, you create a cantrip and cast it:

  // A full cantrip with a medium — this creates a child entity that runs in bash
  var spell = cantrip({
    crystal: "anthropic/claude-3.5-haiku",
    call: "Run the command and report output. Use submit_answer() when done.",
    circle: {
      medium: "bash",
      medium_opts: { cwd: "${repoRoot}" },
      gates: ["done"],
      wards: [{ max_turns: 5 }]
    }
  });
  var result = cast(spell, "Run: git log --oneline -5");

The child gets its own entity loop — it can reason, retry, use tools. When it calls
submit_answer(), you get the result back as a string.

You can also create a leaf cantrip — no circle, no medium, just a single LLM call.
This is useful when you need a child to think about something without needing to
interact with the world:

  // A leaf cantrip — single LLM call, no entity loop
  var thinker = cantrip({ crystal: "anthropic/claude-3.5-haiku", call: "You analyze code for bugs." });
  var analysis = cast(thinker, "Here's a function: " + code + "\\nWhat bugs do you see?");

The crystal field takes any OpenRouter model ID. Pick the right model for the task.
Some options:

  anthropic/claude-haiku-4.5
  openai/gpt-5-mini
  google/gemini-3-flash-preview
  x-ai/grok-4.1-fast
  deepseek/deepseek-v3.2
  moonshotai/kimi-k2.5
  minimax/minimax-m2.5
  z-ai/glm-5

Available mediums: "bash" (shell commands), "js" (another JS runtime), "browser" (headless Chrome).
Available gate sets: "done" (lets the child signal completion).

The handle is consumed when you cast — one cantrip, one cast. If you need to run
the same kind of task again, just create a new cantrip. You can also dispose() a
cantrip you created but decided not to cast.

Because you're writing code, you can compose cantrips in loops, conditionals, and
data pipelines — that's the whole point of working in a code medium.

## Strategy

1. First observe — use repo_* functions to understand context before acting
2. Plan — decide what children you need and what capabilities each requires
3. Act — create cantrips and cast them with clear, specific intents
4. Synthesize — gather child results and compose your answer

Children return truncated strings (max 10k chars). If you need detail, ask for it
specifically in your intent. This is by design — you coordinate, they execute.
${
  loomPath
    ? `
## Memory

Your conversation history is persisted at ${loomPath} (JSONL, one turn per line).
You can read it via repo_read() to review what happened in past sessions. This is
your long-term memory — use it to maintain continuity across conversations.
`
    : ""
}
Use submit_answer() when you have a complete answer for the user.`;

// ── Main ─────────────────────────────────────────────────────────────

export async function main(intent?: string) {
  console.log("=== Example 16: The Familiar ===");
  console.log(
    "A long-running coordinator that delegates to child cantrips via code.\n",
  );

  // Resolve intent: explicit param > positional CLI arg > null (REPL)
  const task = intent ?? positionalArg;

  // ── ACP mode ─────────────────────────────────────────────────────
  if (useAcp) {
    console.log("Mode: ACP server (editors connect over stdio)");
    if (memoryWindow > 0)
      console.log(`Memory window: ${memoryWindow} messages`);

    serveCantripACP(async ({ params, sessionId, connection }) => {
      const repoRoot = params.cwd ?? process.cwd();
      const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
      const { loom, loomPath } = createLoom(repoRoot);
      await loom.load();

      const cantripConfig: CantripMediumConfig = {
        mediums: {
          bash: (opts?: { cwd?: string }) =>
            bash({ cwd: opts?.cwd ?? repoRoot }),
          js: (opts?: { state?: Record<string, unknown> }) =>
            js({ state: opts?.state }),
          browser: () => browser({ headless: true, profile: "full" }),
        },
        gates: { done: [done] },
        default_wards: [{ max_turns: 15 }],
        loom,
      };

      const { gates: cGates, overrides: cOverrides } =
        cantripGates(cantripConfig);
      const repoCtx = new RepoContext(repoRoot);

      // Progress → ACP plan updates (child cantrip casts appear as plan entries)
      const onProgress = createAcpProgressCallback(sessionId, connection);

      const depOverrides = new Map<any, any>([
        [getRepoContextDepends, () => repoCtx],
        [progressBinding, () => onProgress],
        ...cOverrides,
      ]);

      const circle = Circle({
        medium: js(),
        gates: [...repoGates, ...cGates],
        wards: [max_turns(50), require_done()],
      });

      const entity = cantrip({
        crystal,
        call: SYSTEM_PROMPT(repoRoot, loomPath),
        circle,
        dependency_overrides: depOverrides,
        loom,
        folding_enabled: true,
      }).invoke();

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
        },
      };
    });

    return "acp-server-started";
  }

  // ── REPL / single-shot ───────────────────────────────────────────
  const repoRoot = process.cwd();
  const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

  // Use ephemeral loom when called programmatically (tests), persistent otherwise
  const ephemeral = !!intent;
  const { loom, loomPath } = createLoom(repoRoot, ephemeral);
  if (!ephemeral) {
    await loom.load();
    if (loom.size > 0) {
      console.log(`Loaded ${loom.size} turns from previous sessions.`);
    }
  }

  // The capability registry — what children can use
  const cantripConfig: CantripMediumConfig = {
    mediums: {
      bash: (opts?: { cwd?: string }) => bash({ cwd: opts?.cwd ?? repoRoot }),
      js: (opts?: { state?: Record<string, unknown> }) =>
        js({ state: opts?.state }),
      browser: () => browser({ headless: true, profile: "full" }),
    },
    gates: { done: [done] },
    default_wards: [{ max_turns: 15 }],
    loom,
  };

  const { gates: cGates, overrides: cOverrides } = cantripGates(cantripConfig);

  // The Familiar's circle: JS medium + repo observation + cantrip construction gates
  const repoCtx = new RepoContext(repoRoot);
  const depOverrides = new Map<any, any>([
    [getRepoContextDepends, () => repoCtx],
    ...cOverrides,
  ]);

  const circle = Circle({
    medium: js(),
    gates: [...repoGates, ...cGates],
    wards: [max_turns(50), require_done()],
  });

  const spell = cantrip({
    crystal,
    call: SYSTEM_PROMPT(repoRoot, loomPath),
    circle,
    dependency_overrides: depOverrides,
    loom,
    folding_enabled: true,
  });

  if (task) {
    // Single-shot: run one intent and exit
    try {
      console.log(`Intent: ${task}\n`);
      const result = await spell.cast(task);
      console.log(`\nResult:\n${result}`);
      return result;
    } finally {
      await circle.dispose?.();
    }
  }

  // REPL: default interactive mode
  const entity = spell.invoke();
  await runRepl({
    entity,
    greeting:
      "Familiar ready. Observes the repo, delegates via child cantrips.\nType your intents. /quit to exit.",
    onTurn:
      memoryWindow > 0
        ? () => {
            const history = entity.history;
            if (history.length > memoryWindow) {
              entity.load_history(history.slice(-memoryWindow));
            }
          }
        : undefined,
    onClose: async () => {
      await circle.dispose?.();
    },
  });

  return "repl-exited";
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
