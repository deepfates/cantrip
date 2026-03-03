---
title: "RAW.works - ypi: a recursive coding agent"
url: "https://raw.works/ypi-a-recursive-coding-agent/"
date_fetched: "2026-02-16"
type: webpage
---

Title: RAW.works - ypi: a recursive coding agent

URL Source: https://raw.works/ypi-a-recursive-coding-agent/

Published Time: 2026-02-12T00:00:00Z

Markdown Content:
February 12, 2026

I built [ypi](https://github.com/rawwerks/ypi) — a recursive coding agent. It’s [Pi](https://github.com/badlogic/pi-mono) that can call itself.

The name comes from the [Y combinator](https://en.wikipedia.org/wiki/Fixed-point_combinator#Y_combinator) in lambda calculus — the fixed-point combinator that enables recursion. (“rpi” has other connotations.)

The idea was inspired by [Recursive Language Models](https://github.com/alexzhang13/rlm) (RLM), which showed that an LLM with a code REPL and a `llm_query()` function can recursively decompose problems, analyze massive contexts, and write code — all through self-delegation.

The idea
--------

Pi already has a bash REPL. I added one function — `rlm_query` — and a system prompt that teaches Pi to use it recursively. Each child gets its own [jj](https://martinvonz.github.io/jj/) workspace for file isolation. That’s the whole trick.

```
┌──────────────────────────────────────────┐
│  ypi (depth 0)                           │
│  Tools: bash, rlm_query                  │
│  Workspace: default                      │
│                                          │
│  > grep -n "bug" src/*.py                │
│  > sed -n '50,80p' src/app.py \          │
│      | rlm_query "Fix this bug"          │
│            │                             │
│            ▼                             │
│    ┌────────────────────────────┐        │
│    │  ypi (depth 1)            │        │
│    │  Workspace: jj isolated   │        │
│    │  Edits files safely       │        │
│    │  Returns: patch on stdout │        │
│    └────────────────────────────┘        │
│                                          │
│  > jj squash --from <child-change>       │
│  # absorb the fix into our working copy  │
└──────────────────────────────────────────┘
```

The recursion works like this: `rlm_query` spawns a child Pi process with the same system prompt and tools. The child can call `rlm_query` too:

```
Depth 0 (root)    → full Pi with bash + rlm_query
  Depth 1 (child) → full Pi with bash + rlm_query, own jj workspace
    Depth 2 (leaf) → full Pi with bash, but no rlm_query (max depth)
```

Each recursive child gets its own [jj workspace](https://martinvonz.github.io/jj/latest/working-copy/), so the parent’s working copy stays untouched. You review child work with `jj diff`, absorb it with `jj squash --from`.

How it works
------------

The architecture maps directly to the Python RLM library:

| Piece | Python RLM | ypi |
| --- | --- | --- |
| System prompt | `RLM_SYSTEM_PROMPT` | `SYSTEM_PROMPT.md` |
| Context / REPL | Python `context` variable | `$CONTEXT` file + bash |
| Sub-call function | `llm_query("prompt")` | `rlm_query "prompt"` |

The key insight: Pi’s bash tool **is** the REPL. `rlm_query`**is**`llm_query()`. No bridge needed.

Guardrails
----------

Recursive agents without guardrails will burn through your API budget. ypi has several:

| Feature | Env var | What it does |
| --- | --- | --- |
| Budget | `RLM_BUDGET=0.50` | Max dollar spend for entire recursive tree |
| Timeout | `RLM_TIMEOUT=60` | Wall-clock limit for entire recursive tree |
| Call limit | `RLM_MAX_CALLS=20` | Max total `rlm_query` invocations |
| Model routing | `RLM_CHILD_MODEL=haiku` | Use cheaper model for sub-calls |
| Depth limit | `RLM_MAX_DEPTH=3` | How deep recursion can go |
| Tracing | `PI_TRACE_FILE=/tmp/trace.log` | Log all calls with timing + cost |

The agent can check its own spend at any time:

```
rlm_cost          # "$0.042381"
rlm_cost --json   # {"cost": 0.042381, "tokens": 12450, "calls": 3}
```

The path here
-------------

ypi went through four approaches before landing on the current design:

1.   **Tool-use REPL** — Pi’s `completeWithTools()`, ReAct loop. Got 77.6% on LongMemEval.
2.   **Python bridge** — HTTP server between Pi and Python RLM. Too complex.
3.   **Pi extension** — Custom provider with search tools. Not true recursion.
4.   **Bash RLM** — `rlm_query` + `SYSTEM_PROMPT.md`. True recursion via bash. This is the one that stuck.

Try it
------

```
curl -fsSL https://raw.githubusercontent.com/rawwerks/ypi/master/install.sh | bash
```

Or via npm/bun:

```
npm install -g ypi
ypi "What does this repo do?"
```

Or without installing:

```
bunx ypi "Refactor the error handling in this repo"
```

Code is at [github.com/rawwerks/ypi](https://github.com/rawwerks/ypi). It’s built on [Pi](https://github.com/badlogic/pi-mono) and inspired by [RLM](https://github.com/alexzhang13/rlm).

* * *
