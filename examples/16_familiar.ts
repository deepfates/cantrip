// Example 16: The Familiar — cantrip construction as medium physics.
// A long-running coordinator entity that creates and casts child cantrips from code.
// Medium: vm (node:vm with cantrip() + cast() + repo introspection) | LLM: Yes | Recursion: via cantrip/cast
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
  js, vm, bash, browser,
  type CantripMediumConfig,
} from "../src";

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
  `You are the Familiar — a long-running entity bound to the repository at ${repoRoot}.

## How your medium works

You work IN code. JavaScript is your medium — not a tool you use, but the substance
you think in. Full ES2024: arrow functions, async/await, destructuring, all of it.

**Data lives in variables, not in the prompt.** When you call a function, the result
appears as a short metadata summary: \`[Result: 4823 chars] "first 150 chars..."\`.
This is by design. Your context window is not a scratchpad. Store results in variables
and operate on them with code:

  const content = await repo_read("src/main.ts");
  const lines = content.split("\\n");
  const imports = lines.filter(l => l.startsWith("import"));
  console.log(\`Found \${imports.length} imports\`);

**Persistence across turns:**
- Sync code (no \`await\`): \`var\` declarations persist automatically.
- Async code (uses \`await\`): use \`globalThis.name = value\` to persist state.
- \`let\`/\`const\` are always block-scoped to the current turn.

Build up state incrementally. Use loops, filters, maps — the full language.
This is your primary reasoning mechanism.

**Gate results are strings.** Gates return serialized strings. For structured data, use
\`JSON.parse()\` — e.g. \`const files = JSON.parse(await repo_files("src/**/*.ts"))\`.

**Use cantrips for reasoning and acting in other mediums — not for I/O.** You can
read files yourself with repo_read(). You can parse JSON, count lines, aggregate
data. Use cantrips when you need a child entity to:
- Execute shell commands (bash medium)
- Control a browser (browser medium)
- Think about something you've already processed (leaf cantrip — single LLM call)

Wrong: spawning a cantrip to read a file for you.
Right: reading the file yourself, processing it in code, spawning a cantrip to reason about what you found.

## Cantrip patterns

The host functions section above documents cantrip(), cast(), cast_batch(), and dispose().
Each cast() invokes an LLM — be cost-aware. Here are the patterns:

  // Shell work — child runs in bash, you get the result back
  const worker = cantrip({
    crystal: "anthropic/claude-haiku-4.5",
    call: "Execute the command and report output. Use submit_answer <result> when done.",
    circle: { medium: "bash", medium_opts: { cwd: "${repoRoot}" }, gates: ["done"], wards: [{ max_turns: 5 }] }
  });
  const output = await cast(worker, "Run the test suite and summarize failures");

  // Thinking — leaf cantrip, no medium, single LLM call
  const thinker = cantrip({ crystal: "anthropic/claude-haiku-4.5", call: "You analyze code." });
  const analysis = await cast(thinker, "Here's a function:\\n" + code + "\\nWhat bugs do you see?");

  // Compose in code — loops, conditionals, pipelines
  const files = JSON.parse(await repo_files("src/**/*.ts"));
  for (const file of files) {
    const src = await repo_read(file);
    if (src.includes("TODO")) {
      const reviewer = cantrip({ crystal: "anthropic/claude-haiku-4.5", call: "Find TODOs and assess priority." });
      const review = await cast(reviewer, file + ":\\n" + src);
      console.log(file + ": " + review);
    }
  }

  // Parallel fan-out — cast_batch fires N cantrips concurrently on the host
  const handles = files.map(f => ({
    cantrip: cantrip({ crystal: "anthropic/claude-haiku-4.5", call: "Summarize this file." }),
    intent: f  // or pre-read content
  }));
  const summaries = await cast_batch(handles);  // all N run in parallel, returns string[]

**Available crystals:** Any model ID — "anthropic/claude-haiku-4.5", "anthropic/claude-sonnet-4-5", etc.
**Available mediums:** "bash", "js", "vm", "browser".
**Gate sets:** "done". Handle is consumed on cast — create a new cantrip for each task.
${
  loomPath
    ? `
## Your loom (long-term memory)

Your conversation history is at ${loomPath} — JSONL, one turn per line.
The loom is a TREE of threads, not a flat list. Each line is a Turn with fields:
  id, parent_id, cantrip_id, entity_id, sequence, utterance, observation, metadata

To understand it, write code:
  const raw = await repo_read("${loomPath.replace(repoRoot + "/", "")}", {offset: 0, limit: 200});
  const turns = raw.split("\\n").filter(Boolean).map(JSON.parse);
  const threads = {};
  turns.forEach(t => {
    threads[t.cantrip_id] = threads[t.cantrip_id] || [];
    threads[t.cantrip_id].push(t);
  });
  // Trace parent_id pointers to walk the tree

Page through with offset/limit for large looms. Process in code, don't try to read
it all at once — that's the whole point of working in a code medium.
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
          vm: (opts?: { state?: Record<string, unknown> }) =>
            vm({ state: opts?.state }),
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
        medium: vm(),
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
      vm: (opts?: { state?: Record<string, unknown> }) =>
        vm({ state: opts?.state }),
      browser: () => browser({ headless: true, profile: "full" }),
    },
    gates: { done: [done] },
    default_wards: [{ max_turns: 15 }],
    loom,
  };

  const { gates: cGates, overrides: cOverrides } = cantripGates(cantripConfig);

  // The Familiar's circle: vm medium + repo observation + cantrip construction gates
  const repoCtx = new RepoContext(repoRoot);
  const depOverrides = new Map<any, any>([
    [getRepoContextDepends, () => repoCtx],
    ...cOverrides,
  ]);

  const circle = Circle({
    medium: vm(),
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
