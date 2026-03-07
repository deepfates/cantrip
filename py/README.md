# cantrip — Python

> Python realization. Clean API, in-process Python sandbox, and the most readable code medium examples.

This is the Python realization of the cantrip spec. It was generated from SPEC.md after the TypeScript reference implementation stabilized, then refined interactively as the spec evolved through v0.2 and v0.3. It implements the full domain model — cantrip, entity, circle, gates, wards, mediums, loom — in idiomatic Python with minimal dependencies.

For the full vocabulary and behavioral rules, see [SPEC.md](../SPEC.md) at the repo root.

---

## Quick Start

```bash
cd py
pip install -e .    # or: uv pip install -e .
cp .env.example .env   # add your API key
```

Run the simplest meaningful example:

```bash
python examples/patterns/04_cantrip.py
```

Run all examples in scripted mode (no API key needed):

```bash
uv run pytest tests/test_grimoire_examples.py -q
```

---

## Minimal Example

```python
from cantrip import Cantrip, Circle, Identity, OpenAICompatLLM

# LLM — any OpenAI-compatible endpoint
llm = OpenAICompatLLM(model="gpt-4.1-mini", api_key="sk-...")

# Circle — gates + wards
circle = Circle(gates=["done"], wards=[{"max_turns": 10}])

# Identity — system prompt
identity = Identity(
    system_prompt="You are a financial analyst. Call done(answer) with your summary."
)

# Cantrip — llm + identity + circle
spell = Cantrip(llm=llm, identity=identity, circle=circle)

# Cast it on an intent
result = spell.cast("Revenue up 14% QoQ, churn down 2 points. What does this mean?")
print(result)
```

No medium specified — the circle defaults to **conversation** mode, where gates appear as JSON tool calls. Set `medium="code"` to upgrade the entity's action space to a Python sandbox.

---

## Core API

### Cantrip

The central object. Binds an LLM, an identity, and a circle into a reusable script.

```python
spell = Cantrip(
    llm=llm,
    identity=Identity(system_prompt="..."),
    circle=Circle(
        gates=["done", "call_entity"],
        wards=[{"max_turns": 10}, {"max_depth": 2}],
        medium="code",
    ),
)

# One-shot
result = spell.cast("Analyze this data")

# With thread metadata
result, thread = spell.cast_with_thread("Analyze this data")
print(thread.turns, thread.terminated, thread.truncated)

# Streaming
for event in spell.cast_stream("Analyze this data"):
    print(event)
```

### Entity (Persistent)

A summoned entity survives its first intent. State accumulates across sends.

```python
entity = spell.summon()
first = entity.send("Set up the analysis framework")
second = entity.send("Now analyze Q3 revenue")  # remembers the first send
```

### Circle

The capability envelope: medium + gates + wards.

```python
# Conversation (default) — gates as JSON tool calls
Circle(gates=["done", "echo"], wards=[{"max_turns": 5}])

# Code medium — entity writes Python in a sandbox
Circle(gates=["done", "repo_read"], wards=[{"max_turns": 10}], medium="code")

# Gates with dependencies
Circle(
    gates=["done", {"name": "repo_read", "depends": {"root": "/data"}}],
    wards=[{"max_turns": 10}],
)
```

Built-in gates: `done`, `echo`, `read`, `repo_files`, `repo_read`, `call_entity`, `call_entity_batch`, `fetch`.

### Identity

Immutable configuration: system prompt + hyperparameters.

```python
Identity(
    system_prompt="You analyze code for bugs.",
    require_done_tool=True,     # entity must call done() explicitly
    temperature=0.7,
)
```

### Loom

Append-only turn storage. Every turn is recorded before the next begins.

```python
from cantrip import Loom, InMemoryLoomStore, SQLiteLoomStore

# In-memory (ephemeral)
loom = Loom(store=InMemoryLoomStore())

# Persistent to disk
loom = Loom(store=SQLiteLoomStore("loom.db"))

# Attach to a cantrip
spell = Cantrip(llm=llm, identity=identity, circle=circle, loom=loom)
```

---

## Mediums

### Conversation (default)

No medium specified. Gates appear as JSON tool calls — the LLM sees each gate as a separate tool definition. This is how most agent frameworks work.

```python
Circle(gates=["done", "echo"], wards=[{"max_turns": 5}])
```

### Code Medium

The entity writes Python code that executes in-process via `exec()`. Gates are projected as host functions — `done()`, `call_gate()`, `call_entity()` — callable directly in the sandbox. Variables persist across turns.

```python
Circle(
    gates=["done", "repo_read"],
    wards=[{"max_turns": 10}],
    medium="code",
)
```

In the sandbox, the entity writes:

```python
# Turn 1
data = call_gate("repo_read", {"path": "metrics.txt"})

# Turn 2 — data persists from turn 1
lines = data.split("\n")
done(f"Found {len(lines)} metrics")
```

The code medium uses `InProcessPythonExecutor` by default — Python's `exec()` with warded builtins and injected host functions. This gives the entity access to Python's full standard library within the sandbox, but isolation is best-effort (CPython threads can't be force-killed). For stronger isolation, use `SubprocessPythonExecutor`.

### Browser Medium

Adds browser automation via Playwright. Requires the `browser` optional dependency.

---

## Composition

The entity delegates via `call_entity` in code medium. Delegation is synchronous — the parent blocks while the child runs.

```python
spell = Cantrip(
    llm=parent_llm,
    child_llm=child_llm,  # optional: different LLM for children
    circle=Circle(
        medium="code",
        gates=["done", "call_entity"],
        wards=[{"max_turns": 6}, {"max_depth": 2}],
    ),
    identity=Identity(
        system_prompt="Delegate tasks to children via call_entity.",
        require_done_tool=True,
    ),
)
```

Inside the code medium, the entity writes:

```python
# call_entity is synchronous — blocks and returns the child's answer as a string
trends = call_entity({"intent": "Identify top 3 trends in this data..."})
risks = call_entity({"intent": "What are the biggest risks..."})
done(f"Trends: {trends}\nRisks: {risks}")
```

Children get a generic system prompt and independent context (COMP-4). Delegation gates are stripped from children to prevent recursive delegation. Child max_turns is capped at 3.

---

## Examples

Twelve examples in `examples/patterns/`, one for each grimoire pattern. Each example works in two modes: **scripted** (deterministic, no API key) and **real** (live LLM calls).

| # | Pattern | What it teaches |
|---|---------|----------------|
| 01 | `llm_query` | LLM as stateless query |
| 02 | `gate` | Direct gate execution |
| 03 | `circle` | Construction invariants (done gate, wards) |
| 04 | `cantrip` | LLM + identity + circle = reusable script |
| 05 | `wards` | Subtractive composition (min for numeric, OR for boolean) |
| 06 | `medium` | Tool medium vs code medium — same gates, different action space |
| 07 | `full_agent` | Code medium + filesystem gates + error steering |
| 08 | `folding` | Context compression for long runs |
| 09 | `composition` | call_entity + call_entity_batch |
| 10 | `loom` | Inspect the append-only artifact |
| 11 | `persistent_entity` | summon/send across episodes |
| 12 | `familiar` | Persistent coordinator delegating through code |

Run any example:
```bash
python examples/patterns/04_cantrip.py
```

---

## What You Can Learn Here

**Strengths:**

- **Readable code medium examples.** The Python examples are the clearest demonstration of the conversation-vs-code medium distinction. Example 06 shows the same gates producing different action spaces. Example 07 shows error steering in a code sandbox.
- **In-process Python sandbox.** The entity writes Python that runs via `exec()` with injected host functions. This is the most natural code medium if you're building in Python — the entity writes the same language as the host.
- **Clean API surface.** `Cantrip`, `Identity`, `Circle` — three classes, frozen dataclasses, no framework magic. The public API is 18 symbols.
- **SQLite loom storage.** The only implementation with SQLite as a loom backend (vs JSONL or in-memory). Good for persistent entities that need durable turn history.
- **Protocol adapters.** ACP (stdio), HTTP, and CLI adapters are all included and tested.

**Limitations:**

- **One LLM provider.** `OpenAICompatLLM` only — works with OpenAI, OpenRouter, and any OpenAI-compatible endpoint, but no native Anthropic or Google adapters. (The TS implementation has five providers.)
- **Two mediums.** Conversation and code (plus browser with optional Playwright). No bash, VM, or other substrate mediums.
- **In-process isolation only.** The default `InProcessPythonExecutor` uses `exec()` — no security boundary. `SubprocessPythonExecutor` is available but can't share gate functions across the process boundary. Neither is as isolated as QuickJS or node:vm.
- **`MiniCodeExecutor` is vestigial.** A minimal JS interpreter in Python, exported and tested but unlikely to be useful outside of cross-language test compatibility.

---

## Spec Conformance

Tests: **227 pass, 2 skip** (`uv run pytest tests/ -q`)

The test suite includes:
- Core lifecycle tests (entity, cantrip, circle, loom)
- Medium behavior tests (tool and code)
- End-to-end delegation tests
- Grimoire example tests (all 12 patterns)
- Spec MUST-rule coverage test (regex scan of SPEC.md rules vs implementation)
- Protocol adapter tests (ACP, HTTP, CLI)

---

## Setup

Requires Python 3.11+.

```bash
pip install -e .    # or: uv pip install -e .
cp .env.example .env
```

Dependencies: `requests`, `PyYAML`, `agent-client-protocol`. No heavy ML frameworks.

Set your API key:
```bash
OPENAI_API_KEY="sk-..."
OPENAI_MODEL="gpt-4.1-mini"
# Optional:
OPENAI_BASE_URL="https://api.openai.com/v1"
```

Run tests:
```bash
uv run pytest tests/ -q
```
