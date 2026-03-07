# 📜 cantrip

> "The cantrips have been spoken. The patterns of force are aligned. Now it is up to your machine."
> >
> — Gargoyles: Reawakening (1995)

Cantrip is a pattern for building LLM entities — autonomous loops where a model acts in an environment, observes the results, and adapts. You draw a circle, speak an intent into it, and an entity arises. It reasons, writes code, calls tools, delegates to children, and loops until the work is done or a limit is reached.

Three components make a cantrip: the **LLM** (the model), the **identity** (a system prompt that shapes it), and the **circle** (the environment it acts in). The circle contains a **medium** — the substrate the entity works *in*, like a code sandbox or a conversation — plus **gates** (functions that cross the boundary, like reading files or spawning child entities) and **wards** (hard constraints like turn limits that the entity cannot override). The entity's action space follows a formula: **A = M ∪ G − W**. Everything the medium and gates allow, minus whatever the wards restrict.

Cast a cantrip on an intent and the entity loops until it calls `done` or a ward cuts it off. Every turn is recorded in the **loom** — an append-only tree that captures the full execution history. Threads that end with `done` are *terminated* (complete episodes). Threads cut short by wards are *truncated* (interrupted). The distinction matters if you use the loom for training data.

The pattern is defined by a [spec](./SPEC.md) and a [behavioral test suite](./tests.yaml). This repository contains four working implementations you can run, learn from, or use as a starting point for your own.

## Launch the Familiar

The fastest way to experience cantrip is the Familiar — a persistent entity that observes a codebase, reasons in a code sandbox, and delegates to child entities with different capabilities (shell, browser, analysis). It constructs new cantrips at runtime from code.

```bash
cd ts && bun install
cp .env.example .env    # add your API key
bun run examples/16_familiar.ts
```

Ask it to explore the repo, run tests, analyze files — it figures out how to decompose the task and coordinate the work.

To start simpler, run example 04 — that's where the core vocabulary (LLM + identity + circle = cantrip) clicks:

```bash
bun run examples/04_cantrip.ts
```

## What's in the spellbook

**[SPEC.md](./SPEC.md)** — The formal specification. This is the durable artifact — everything else regenerates from it.

**[tests.yaml](./tests.yaml)** — Behavioral tests for every rule in the spec.

**Four implementations**, each teaching something different:

- **[ts/](./ts)** — The reference implementation. The most mediums, the most examples, the fullest coverage. Start here to see everything cantrip can do.
- **[py/](./py)** — The most readable. Clean API, Python sandbox. Start here to understand the pattern by reading code.
- **[clj/](./clj)** — Clojure with a sandboxed interpreter. Idiomatic immutable data, good for studying the domain model.
- **[ex/](./ex)** — Elixir on OTP. Each entity is a supervised process. The most production-oriented architecture.

Each has its own README with setup, API docs, examples, and an honest assessment of what it does well and where it falls short.

## The example progression

Every implementation follows the same twelve-step arc from the spec's grimoire (Appendix A). Each example adds one concept to the previous:

**Query** → **Gate** → **Circle** → **Cantrip** → **Wards** → **Medium** → **Codex** → **Folding** → **Composition** → **Loom** → **Persistence** → **Familiar**

The TypeScript implementation extends this with nine additional examples covering extra mediums (VM, bash, browser) and advanced patterns. The other three implementations cover the core twelve.

Start at 04 (cantrip). Work forward. The familiar is where everything converges.

## How to use this

This is a reference point, not a library you install. The ideal path:

1. Run example 04 in any implementation to see the pattern in action.
2. Read the [spec](./SPEC.md) when you want the full vocabulary and rules.
3. Walk the example progression to the familiar.
4. Copy the spec and tests into your own repo and build your own version.

The implementations are here so you can see the pattern in different languages, learn from them, feed them to an agent, or scrap them for parts.

Copy the spellbook. Cast your own.
