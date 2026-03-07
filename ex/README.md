# cantrip — Elixir

> Elixir realization. OTP supervision, BEAM code medium, multiple storage backends, and the most production-oriented architecture.

This is the Elixir realization of the cantrip spec. It was built spec-first through red-green TDD, with tests organized by milestone and mapped to SPEC.md rule IDs. Each entity runs as a GenServer under a DynamicSupervisor — the OTP process model maps naturally onto the spec's entity lifecycle. The code medium evaluates Elixir on the BEAM, giving entities access to pattern matching, pipes, and the full standard library.

For the full vocabulary and behavioral rules, see [SPEC.md](../SPEC.md) at the repo root.

---

## Quick Start

```bash
cd ex
mix deps.get
cp .env.example .env   # add your API key
```

Run the test suite:

```bash
mix test
```

Run an example in scripted mode (no API key needed):

```bash
mix cantrip.example 04 --fake
```

List all available examples:

```bash
mix cantrip.example list
```

---

## Minimal Example

```elixir
# LLM — any OpenAI-compatible endpoint
{:ok, cantrip} =
  Cantrip.new(%{
    llm_module: Cantrip.LLMs.OpenAICompatible,
    llm_state: %{model: "gpt-4.1-mini", api_key: "sk-..."},
    identity: %Cantrip.Identity{
      system_prompt: "You are a financial analyst. Call done(answer) with your summary."
    },
    circle: %Cantrip.Circle{
      gates: %{"done" => %{name: "done"}},
      wards: [%{max_turns: 10}]
    }
  })

# Cast it on an intent
{:ok, result, _cantrip, _loom, _meta} =
  Cantrip.cast(cantrip, "Revenue up 14% QoQ, churn down 2 points. Summarize.")
```

Or construct from environment variables:

```elixir
{:ok, cantrip} =
  Cantrip.new_from_env(
    circle: %{gates: [:done], wards: [%{max_turns: 10}]}
  )
```

---

## Core API

### `Cantrip.new/1`

Validates and constructs a cantrip struct. Enforces CANTRIP-1 (requires LLM, identity, circle), CIRCLE-1 (requires done gate), CIRCLE-2 (requires truncation ward).

### `Cantrip.cast/2`

One-shot: spawns a GenServer, runs the loop, returns the result, stops the process.

```elixir
{:ok, result, cantrip, loom, meta} = Cantrip.cast(cantrip, "Analyze this data")
```

### `Cantrip.summon/1` / `Cantrip.send/2`

Persistent entity: the GenServer stays alive across intents.

```elixir
{:ok, pid} = Cantrip.summon(cantrip)
{:ok, r1, _, _, _} = Cantrip.send(pid, "Set up the framework")
{:ok, r2, _, _, _} = Cantrip.send(pid, "Now analyze Q3")  # remembers r1
```

### `Cantrip.cast_stream/2`

Streaming: returns a `{stream, task}` pair. The stream yields `{:cantrip_event, event}` tuples as they occur.

```elixir
{stream, task} = Cantrip.cast_stream(cantrip, "Analyze this data")
Enum.each(stream, fn {:cantrip_event, event} -> IO.inspect(event) end)
{:ok, result, _, _, _} = Task.await(task)
```

### `Cantrip.fork/4`

Restart from a prior turn. The code medium's state is snapshot at each turn, enabling fork without replay.

---

## Circle

The capability envelope: medium + gates + wards. The formula is `A = M ∪ G − W`.

```elixir
# Conversation medium (default)
%Cantrip.Circle{
  type: :conversation,
  gates: %{"done" => %{name: "done"}, "echo" => %{name: "echo"}},
  wards: [%{max_turns: 5}]
}

# Code medium — entity writes Elixir
%Cantrip.Circle{
  type: :code,
  gates: %{"done" => %{name: "done"}, "call_entity" => %{name: "call_entity"}},
  wards: [%{max_turns: 10}, %{max_depth: 2}]
}
```

Built-in gates: `done`, `echo`, `read`, `call_entity`, `call_entity_batch`, `compile_and_load`.

---

## Mediums

### Conversation (default)

Gates appear as tool definitions. The LLM returns structured tool calls. Standard chat agent pattern.

### Code (BEAM Evaluation)

The entity writes Elixir code that evaluates on the BEAM via `Code.eval_quoted`. Bindings persist across turns. Gates are injected as anonymous functions.

```elixir
# In the sandbox, the entity writes:

# Turn 1
data = echo.(%{text: "Q3 revenue up 14%"})

# Turn 2 — data persists
done.("Analysis: #{data}")
```

Available host functions: `done.(answer)`, `call_entity.(opts)`, `call_entity_batch.(list)`, `call_gate.(name, args)`, `compile_and_load.(opts)`, plus any custom gates.

**Important:** `call_entity` is **synchronous** — blocks and returns the child's answer. `done` throws internally to terminate the loop.

Reserved bindings (`done`, `call_entity`, etc.) cannot be overridden by user code. User-defined variables persist across turns by filtering out functions from the binding snapshot.

---

## Composition

In code medium, the entity delegates via `call_entity`:

```elixir
# Parent writes this in the Elixir sandbox:
trends = call_entity.(%{intent: "Identify top 3 trends in Q3 data..."})
risks = call_entity.(%{intent: "What are the biggest risks..."})
done.("Trends: #{trends}\nRisks: #{risks}")
```

Note the dot-call syntax — gates are anonymous functions in Elixir's sandbox (`call_entity.(args)`, not `call_entity(args)`).

Children get a generic system prompt, no delegation gates, and capped max_turns.

---

## Loom and Storage

Append-only turn storage with pluggable backends:

```elixir
# In-memory (default, ephemeral)
Cantrip.new(%{..., loom_storage: :memory})

# DETS (Erlang disk-based key-value store)
Cantrip.new(%{..., loom_storage: {:dets, "loom.dets"}})

# Mnesia (Erlang relational database)
Cantrip.new(%{..., loom_storage: {:mnesia, %{table: :cantrip_turns}}})

# JSONL (JSON Lines file)
Cantrip.new(%{..., loom_storage: {:jsonl, "loom.jsonl"}})

# Auto (tries Mnesia, falls back to DETS)
Cantrip.new(%{..., loom_storage: {:auto, %{dets_path: "loom.dets"}}})
```

Five storage backends — the broadest selection of any implementation. Mnesia gives you distributed, replicated turn storage across BEAM nodes if you need it.

---

## Hot-Reload Gate

The `compile_and_load` gate lets the entity hot-load Elixir modules at runtime. This is guarded by four ward types:

- `allow_compile_modules` — whitelist of module names
- `allow_compile_paths` — whitelist of file paths
- `allow_compile_sha256` — whitelist of source code hashes
- `allow_compile_signers` — map of key IDs to PEM public keys for signature verification

This is unique to the Elixir implementation — no other realization has code-signing-gated hot reload.

---

## ACP (Agent Communication Protocol)

Run the ACP stdio server:

```bash
mix cantrip.acp
```

Or as an installed escript:

```bash
mix escript.install
cantrip acp
```

Zed custom agent configuration:

```json
{
  "agent_servers": {
    "cantrip-ex": {
      "type": "custom",
      "command": "mix",
      "args": ["cantrip.acp"],
      "cwd": "/path/to/cantrip/ex"
    }
  }
}
```

Protocol: `initialize`, `session/new`, `session/prompt` over JSON-RPC stdio.

---

## Examples

Twelve examples matching the grimoire progression (Appendix A).

| # | Pattern | What it teaches |
|---|---------|----------------|
| 01 | LLM Query | Stateless round-trip (LLM-1) |
| 02 | Gate | Direct execution + done semantics (CIRCLE-1) |
| 03 | Circle | Construction invariants — missing done/ward errors |
| 04 | Cantrip | Reusable value, independent casts (CANTRIP-2) |
| 05 | Wards | Subtractive composition (WARD-1) |
| 06 | Medium | Conversation vs code — A = M ∪ G − W |
| 07 | Full Agent | Filesystem + compile_and_load + error steering |
| 08 | Folding | Context compression for long runs |
| 09 | Composition | call_entity + call_entity_batch (COMP-2, COMP-3) |
| 10 | Loom | Inspect the append-only artifact |
| 11 | Persistent Entity | summon/send across episodes (ENTITY-5) |
| 12 | Familiar | Child cantrips through code delegation |

Run any example:
```bash
mix cantrip.example 04         # with real LLM (needs .env)
mix cantrip.example 04 --fake  # scripted mode
mix cantrip.example 04 --json  # machine-readable output
```

---

## What You Can Learn Here

**Strengths:**

- **OTP process model.** Each entity is a GenServer under a DynamicSupervisor. The spec's entity lifecycle (summon → send → send → terminate) maps directly onto OTP process semantics — `start_link`, `call`, `stop`. If you're building a production system that needs entity isolation and supervision, this is the architecture to study.
- **Five storage backends.** Memory, DETS, Mnesia, JSONL, and Auto. Mnesia gives you distributed, replicated loom storage across BEAM nodes. No other implementation offers this.
- **BEAM code medium.** The entity writes Elixir — pattern matching, pipes, comprehensions, the full standard library. Bindings persist across turns via `Code.eval_quoted`. This is what a "native" code medium looks like when the host language is the sandbox language.
- **Hot-reload with crypto signatures.** The `compile_and_load` gate lets entities load new modules at runtime, gated by SHA-256 hashes or public key signatures. Unique to this implementation.
- **Red-green test organization.** Tests are split by milestone (`m1_*.exs` through `m24_*.exs`), mapped to spec rule families. Good for understanding which tests verify which behavioral rules.
- **Three LLM adapters.** OpenAI-compatible, Anthropic (native), and Gemini — more provider coverage than Python or Clojure.

**Limitations:**

- **Two mediums only.** Conversation and code. No bash, browser, or VM equivalents.
- **Elixir dot-call syntax.** Gates are anonymous functions, so the entity writes `done.(answer)` not `done(answer)`. LLMs sometimes struggle with this, especially for complex code patterns.
- **No conformance runner.** Tests are written directly in ExUnit, not derived from tests.yaml. The Clojure implementation's conformance runner is more directly traceable to the spec's test suite.
- **`erl_crash.dump` in the directory.** Leftover from a crash during development. Harmless but not cleaned up.

---

## Architecture

```
lib/cantrip/
├── entity_server.ex      # GenServer: owns one cast execution (~700 lines)
├── entity_supervisor.ex   # DynamicSupervisor for entity processes
├── circle.ex              # Gate/ward model + execution (530 lines)
├── code_medium.ex         # BEAM code evaluation sandbox
├── identity.ex            # Immutable call configuration
├── llm.ex                 # LLM behavior + contract validation
├── loom.ex                # Append-only turn storage
├── loom/storage/          # Memory, DETS, Mnesia, JSONL, Auto backends
├── llms/                  # OpenAI-compatible, Anthropic, Gemini adapters
├── fake_llm.ex            # Deterministic scripted LLM
├── examples.ex            # 12 teaching examples
├── acp/                   # ACP protocol, runtime, server
├── repl.ex                # Interactive REPL
└── application.ex         # OTP application (starts supervisor)
```

Dependencies: Elixir 1.15+, `jason` (JSON), `req` (HTTP). No heavy frameworks.

---

## Spec Conformance

Tests: **170 tests, 0 failures** (`mix test`)

Test suites cover: LLM contract, config invariants, loom semantics, loop runtime, circle execution, composition (basic + extended + cancellation), production semantics (retry, folding, ephemeral), hot-reload, ACP protocol, streaming, persistent entities, and all 12 examples.

---

## Setup

Requires Elixir 1.15+ and Erlang/OTP 26+.

```bash
mix deps.get
cp .env.example .env
```

Set your API key:
```bash
CANTRIP_LLM_PROVIDER=openai_compatible
CANTRIP_MODEL=gpt-4.1-mini
CANTRIP_API_KEY=sk-...
CANTRIP_BASE_URL=https://api.openai.com/v1
```

Run tests:
```bash
mix test
```

Interactive REPL:
```bash
mix cantrip.repl
```
