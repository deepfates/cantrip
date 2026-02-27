# cantrip

> "The cantrips have been spoken. The patterns of force are aligned. Now it is up to your machine."
> — Gargoyles: Reawakening (1995)


A framework for building autonomous LLM entities. You draw a circle, speak an intent into it, and an entity arises — it reasons, acts in an environment, observes the results, and loops until the work is done or a limit is reached.

Eleven terms describe everything in the system. Three are fundamental: the **crystal** (the model), the **call** (the invocation that shapes it), and the **circle** (the environment it acts in). Everything else is what happens when you put those together and let the loop run.

---

## Quick Start: Launch an Entity

The fastest way to experience cantrip is to launch the **Familiar** — a long-running entity that can explore a codebase, run shell commands, browse the web, and reason about what it finds. It works in a JS medium and delegates to child cantrips with different mediums (bash, browser, etc.).

```bash
# Clone and install
git clone https://github.com/deepfates/cantrip.git
cd cantrip
bun install

# Set your API key
export ANTHROPIC_API_KEY="sk-..."

# Launch the Familiar as an interactive REPL
bun run examples/16_familiar.ts
```

You'll get an interactive session where the entity can observe the repo (`repo_files`, `repo_read`), spawn child cantrips to run shell commands or browse the web, and reason about everything in code. Ask it to explore the codebase, run tests, analyze files — it figures out how to decompose the task and coordinate the work.

```bash
# Or give it a single task
bun run examples/16_familiar.ts "Explain the gate system and find all builtin gates"
```

The `examples/` directory has simpler starting points too — see the [examples table](#examples) below to walk through the concepts one at a time.

---

## Minimal Example

To build a cantrip from scratch: a crystal, a circle with gates and wards, and a call.

```typescript
import { cantrip, Circle, ChatAnthropic, done, max_turns, gate } from "cantrip";

// Crystal — an LLM
const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });

// A gate — a function the entity can call
const add = gate("Add two numbers", async ({ a, b }: { a: number; b: number }) => a + b, {
  name: "add",
  params: { a: "number", b: "number" },
});

// Circle — gates + wards (constraints)
const circle = Circle({
  gates: [add, done],
  wards: [max_turns(10)],
});

// Cantrip — crystal + call + circle
const spell = cantrip({
  crystal,
  call: "You are a calculator. Use the add tool, then call done with the result.",
  circle,
});

// Cast it on an intent
const result = await spell.cast("What is 2 + 3?");
console.log(result); // "5"
```

Each `cast` creates a fresh entity — the cantrip is a reusable recipe. No medium specified here: the circle uses **conversation** by default, where gates appear as tool calls in natural language. Add a medium to upgrade the entity's action space — see [Mediums](#mediums) below.

---

## Core Concepts

### Crystal (Cognition)

A crystal wraps an LLM. It takes messages and tools, returns a response. Stateless — each query is independent.

```typescript
import { ChatAnthropic } from "cantrip";

const crystal = new ChatAnthropic({ model: "claude-sonnet-4-5" });
const result = await crystal.query([
  { role: "user", content: "What is 2 + 2? Reply with just the number." },
]);
console.log(result.content); // "4"
```

Multiple providers: `ChatAnthropic`, `ChatOpenAI`, `ChatGoogle`, `ChatOpenRouter`, `ChatLMStudio`.

### Call (Invocation)

The call shapes the entity's behavior — a system prompt plus any hyperparameters. It can be a string or an object:

```typescript
// String shorthand
cantrip({ crystal, call: "You analyze code for bugs.", circle });

// Object form
cantrip({
  crystal,
  call: { system_prompt: "You analyze code for bugs." },
  circle,
});
```

Gate definitions are automatically derived from the circle — you don't wire them manually.

### Circle (Control)

A circle is the entity's capability envelope: **medium + gates + wards**.

```typescript
import { Circle, done, max_turns, require_done } from "cantrip";

const circle = Circle({
  gates: [done],
  wards: [max_turns(10)],
});
```

Every circle must have a `done` gate (how the entity signals completion) and at least one ward (how the host prevents infinite loops). This is enforced at construction time.

**Gates** are functions bound into the circle from outside. The entity calls them as tools:
- `done` — signals task completion via `submit_answer(result)`
- Custom gates — any function you define with `gate()`
- Builtin sets — `safeFsGates` (filesystem), `repoGates` (repo observation), `cantripGates` (child cantrip construction)

**Wards** are constraints on the loop:
- `max_turns(n)` — limit loop iterations
- `require_done()` — only explicit `done` terminates (text-only responses don't stop the loop)

### Entity (Emergence)

An entity is what arises when you cast a cantrip on an intent. You don't build it — it emerges from the loop. It accumulates context, develops strategies, and adapts turn by turn.

Two ways to create one:

```typescript
// Cast — one-shot. Entity runs, returns result, disposes.
const result = await spell.cast("Analyze this data");

// Invoke — persistent. Entity survives, accepts more intents.
const entity = spell.invoke();
const r1 = await entity.cast("First task");
const r2 = await entity.cast("Follow-up task"); // remembers r1
```

For interactive sessions, use `invoke()` with the built-in REPL:

```typescript
import { runRepl } from "cantrip";

const entity = spell.invoke();
await runRepl({
  entity,
  greeting: "Agent ready. Ctrl+C to exit.",
});
```

---

## Mediums

A **medium** is the substrate the entity works in. When no medium is specified, the circle uses **conversation** — the baseline where gates appear as tool calls in natural language. Add a medium to upgrade the entity's action space.

One medium per circle. The medium replaces conversation — it doesn't sit alongside it. The entity works *in* the medium, not through it.

### Conversation (default)

No medium specified. The entity communicates in natural language and uses gates as tool calls. This is how most chat-based agents work.

```typescript
const circle = Circle({
  gates: [...safeFsGates, done],
  wards: [max_turns(100)],
});
```

### VM (node:vm sandbox)

The entity writes and runs JavaScript in a node:vm context. Full ES2024 — arrow functions, async/await, destructuring. Zero external dependencies. Gates are projected as async functions the entity calls with `await`.

```typescript
import { vm } from "cantrip";

const circle = Circle({
  medium: vm({ state: { context: { items: [1, 2, 3] } } }),
  wards: [max_turns(20), require_done()],
});
```

The entity sees a `context` variable in its sandbox and explores it with code. `var` and `globalThis` persist across turns. Weak isolation (V8 context, not a security boundary).

### JavaScript (QuickJS sandbox)

The entity works in a QuickJS WASM sandbox. Strong isolation but limited ES version and a serialization boundary — gate results are strings, not native objects.

```typescript
import { js } from "cantrip";

const circle = Circle({
  medium: js({ state: { context: { items: [1, 2, 3] } } }),
  wards: [max_turns(20), require_done()],
});
```

### Bash

The entity writes shell commands. Full access to CLI tools — git, curl, ffmpeg, jq, whatever's installed.

```typescript
import { bash } from "cantrip";

const circle = Circle({
  medium: bash({ cwd: "/project" }),
  wards: [max_turns(10)],
});
```

### Browser (Taiko)

The entity controls a headless browser by writing Taiko code — navigation, clicking, data extraction.

```typescript
import { browser } from "cantrip";

const circle = Circle({
  medium: browser({ headless: true, profile: "full" }),
  wards: [max_turns(50), require_done()],
});
```

### jsBrowser

JS sandbox with browser automation combined — the entity writes JavaScript that can also control a browser.

```typescript
import { jsBrowser, BrowserContext } from "cantrip";

const browserCtx = await BrowserContext.create({ headless: true, profile: "full" });
const circle = Circle({
  medium: jsBrowser({ browserContext: browserCtx }),
  wards: [max_turns(200), require_done()],
});
```

### Other mediums

Any interactive environment can become a medium — Python, SQL, Frida, GDB, Redis, or a custom DSL. The interface is the same: the entity writes, the medium executes, the result feeds back.

---

## Patterns

### One-shot cast

The simplest pattern. Create a cantrip, cast it, get a result.

```typescript
import { cantrip, Circle, ChatAnthropic, js, max_turns, require_done } from "cantrip";

const spell = cantrip({
  crystal: new ChatAnthropic({ model: "claude-sonnet-4-5" }),
  call: "Explore the context variable. Use submit_answer() when you have a final answer.",
  circle: Circle({
    medium: js({ state: { context: { items: ["alpha", "beta", "gamma"] } } }),
    wards: [max_turns(20), require_done()],
  }),
});

const answer = await spell.cast("Which item comes first alphabetically?");
```

### Persistent REPL

For interactive sessions — the entity remembers across intents.

```typescript
import { runRepl, safeFsGates, getSandboxContext, SandboxContext } from "cantrip";

const fsCtx = await SandboxContext.create();

const entity = cantrip({
  crystal,
  call: `Coding assistant. Working dir: ${fsCtx.working_dir}`,
  circle: Circle({
    gates: [...safeFsGates, done],
    wards: [max_turns(100)],
  }),
  dependency_overrides: new Map([[getSandboxContext, () => fsCtx]]),
}).invoke();

await runRepl({ entity, greeting: "Agent ready." });
```

### Recursive delegation

A parent entity in a JS medium delegates subtasks to children via `call_entity`.

```typescript
import { call_entity_gate, Loom, MemoryStorage, js } from "cantrip";

const entityGate = call_entity_gate({ max_depth: 2, depth: 0, parent_context: data });

const circle = Circle({
  medium: js({ state: { context: data } }),
  gates: entityGate ? [entityGate] : [],
  wards: [max_turns(20), require_done()],
});

const loom = new Loom(new MemoryStorage());
const spell = cantrip({ crystal, call: "Delegate analysis to child entities.", circle, loom });
const answer = await spell.cast("Analyze each category and summarize the trend.");
```

Children get independent circles. The shared loom captures parent + child turns as a tree.

### The Familiar

The capstone pattern: a long-running entity in a `vm()` medium that creates and casts child cantrips from code. It observes the repo, delegates to specialized children (bash, browser, JS), and synthesizes results.

```typescript
import {
  cantripGates, repoGates, RepoContext, Loom, JsonlStorage, done,
  vm, js, bash, browser, getRepoContextDepends,
} from "cantrip";

const loom = new Loom(new JsonlStorage(".cantrip/loom.jsonl"));
await loom.load();

const cantripConfig = {
  mediums: {
    bash: (opts) => bash({ cwd: opts?.cwd ?? repoRoot }),
    js: (opts) => js({ state: opts?.state }),
    vm: (opts) => vm({ state: opts?.state }),
    browser: () => browser({ headless: true, profile: "full" }),
  },
  gates: { done: [done] },
  default_wards: [{ max_turns: 15 }],
  loom,
};

const { gates: cGates, overrides: cOverrides } = cantripGates(cantripConfig);
const repoCtx = new RepoContext(repoRoot);

const circle = Circle({
  medium: vm(),
  gates: [...repoGates, ...cGates],
  wards: [max_turns(50), require_done()],
});

const spell = cantrip({
  crystal,
  call: SYSTEM_PROMPT,
  circle,
  dependency_overrides: new Map([
    [getRepoContextDepends, () => repoCtx],
    ...cOverrides,
  ]),
  loom,
  folding_enabled: true,
});
```

Inside the Familiar's vm medium, the entity writes modern JS to coordinate:

```javascript
// Shell work — child runs in bash
const worker = cantrip({
  crystal: "anthropic/claude-haiku-4.5",
  call: "Execute the command and report output.",
  circle: { medium: "bash", gates: ["done"], wards: [{ max_turns: 5 }] }
});
const output = await cast(worker, "Run the test suite");

// Thinking — leaf cantrip, single LLM call
const thinker = cantrip({ crystal: "anthropic/claude-haiku-4.5", call: "Analyze code." });
const analysis = await cast(thinker, "What bugs do you see?\n" + code);

// Compose in code — loops, conditionals, pipelines
const files = JSON.parse(await repo_files("src/**/*.ts"));
for (const file of files) {
  const src = await repo_read(file);
  if (src.includes("TODO")) {
    const review = await cast(
      cantrip({ crystal: "anthropic/claude-haiku-4.5", call: "Find TODOs." }),
      src
    );
    console.log(file + ": " + review);
  }
}
```

See `examples/16_familiar.ts` for the full implementation.

---

## The Loom

Every turn is recorded in a **loom** — a structured log that captures the entity's full execution history as a tree of turns.

```typescript
import { Loom, JsonlStorage, MemoryStorage } from "cantrip";

// In-memory (ephemeral)
const loom = new Loom(new MemoryStorage());

// Persistent to disk
const loom = new Loom(new JsonlStorage(".cantrip/loom.jsonl"));
await loom.load();
```

The loom records whether each thread **terminated** (entity called `done`) or was **truncated** (ward triggered). This distinction matters: terminated threads are complete episodes, truncated threads are interrupted ones.

**Folding** compresses old turns to keep the entity's context window manageable while preserving key information. It reads from the loom and writes compressed summaries back into the entity's working state.

---

## The Spec and the Ghost Library

[SPEC.md](./SPEC.md) is the formal specification — eleven terms, behavioral rules, and the design rationale. It describes behavior, not technology: "the circle must provide sandboxed code execution" — not "use QuickJS."

This TypeScript package is the reference implementation. The spec is designed so that implementations in other languages can be generated from it — the **ghost library** pattern, where the spec and its test suite are the durable artifacts and code regenerates from them. A Python cantrip and a TypeScript cantrip are both cantrips. The concepts compose across language boundaries because each language implements its own native mediums while sharing the same circle/gate/ward semantics.

The [bibliography](./BIBLIOGRAPHY.md) traces each idea from first appearance through academic formalization to independent confirmation.

---

## Examples

The `examples/` directory walks through the concepts in order:

| # | Example | What it teaches |
|---|---------|----------------|
| 01 | `crystal` | LLM as stateless query |
| 02 | `gate` | Defining callable functions |
| 03 | `circle` | Gates + wards + validation |
| 04 | `cantrip` | Crystal + call + circle = script |
| 05 | `ward` | Constraints and safety limits |
| 06 | `providers` | Multi-provider crystals |
| 07 | `conversation` | Conversation medium (default) |
| 08 | `js_medium` | QuickJS sandbox |
| 09 | `browser_medium` | Taiko browser automation |
| 10 | `composition` | Parallel delegation via call_entity_batch |
| 11 | `folding` | Context compression |
| 12 | `full_agent` | JS medium + filesystem gates |
| 13 | `acp` | Agent Client Protocol adapter |
| 14 | `recursive` | Depth-limited recursive entities |
| 15 | `research_entity` | jsBrowser + recursion + ACP |
| 16 | `familiar` | Cantrip construction as medium physics |
| 17 | `leaf_cantrip` | Simplest delegation — crystal + call, one LLM call |
| 18 | `vm_medium` | node:vm sandbox — full ES2024, async/await |
| 19 | `bash_medium` | Entity works IN bash as primary medium |
| 20 | `data_exploration` | RLM pattern — data in sandbox, explore with code |
| 21 | `independent_axes` | M, G, W as orthogonal knobs |

Run any example:
```bash
bun run examples/04_cantrip.ts
```

---

## Installation

```bash
bun install cantrip
```

Set your API key for your crystal provider:
```bash
export ANTHROPIC_API_KEY="sk-..."
# or
export OPENROUTER_API_KEY="sk-..."
# or
export OPENAI_API_KEY="sk-..."
```

---

## Why "Cantrip"?

In tabletop RPGs, a cantrip is the simplest spell — it costs nothing to cast and you can cast it repeatedly. The etymology traces to Gaelic *canntaireachd*, a piper's mnemonic chant. It's a loop of language.

Here, a cantrip is a reusable script for creating LLM entities. Configure once, cast many times, compose into larger spells. The loop is the mechanism. The repetition is the point.

---

## License

MIT
