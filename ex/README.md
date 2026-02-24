# Cantrip (Elixir)

Spec-first implementation of the Cantrip loop in idiomatic Elixir, developed in red-green TDD from API boundaries inward.

## Current Scope

Implemented and green:

- Cantrip config invariants and cast/fork lifecycle
- OTP runtime loop (`GenServer` + `DynamicSupervisor`)
- Conversation and code circles (Elixir code medium on BEAM)
- Composition gates: `call_agent`, `call_agent_batch`
- Depth warding, gate subset inheritance, per-call child crystal override
- Loom append-only thread recording with child subtree linkage
- Production semantics:
  - retry as single-turn (`PROD-2`)
  - cumulative usage tracking (`PROD-3`)
  - auto-folding context compaction (`PROD-4`)
  - ephemeral observation redaction (`PROD-5`)
- Guarded hot-reload gate: `compile_and_load` with module/path wards

## Architecture

Core modules:

- `Cantrip`: public API (`new`, `cast`, `fork`) and runtime wiring
- `Cantrip.Call`: immutable call configuration
- `Cantrip.Circle`: gate and ward model + execution semantics
- `Cantrip.EntityServer`: cast execution owner process
- `Cantrip.EntitySupervisor`: dynamic cast supervision
- `Cantrip.Loom`: append-only turn storage
- `Cantrip.Crystal`: crystal adapter behavior
- `Cantrip.FakeCrystal`: deterministic scripted crystal for tests
- `Cantrip.CodeMedium`: BEAM-evaluated code medium with persistent bindings

Loop shape:

1. `Cantrip.new/1` validates crystal/call/circle contract.
2. `Cantrip.cast/2` seeds initial messages with optional system prompt + intent.
3. Each turn:
   - query crystal with full message context and tool definitions
   - execute returned tool calls in order through the circle
   - append turn record to loom
   - stop on `done` or truncation ward
4. Return result + updated cantrip state + loom + cast metadata.

## Red-Green Workflow

Tests are intentionally split by milestone/rule families in `test/m*_*.exs`, so onboarding engineers can map behavior back to `tests.yaml` and `SPEC.md`.

Recommended extension loop:

1. Pick one rule or closely-related cluster from [`tests.yaml`](/Users/deepfates/Hacking/github/deepfates/cantrip-ex/tests.yaml).
2. Add a failing ExUnit test named with the rule ID.
3. Implement the narrowest code change to pass.
4. Refactor only after green.
5. Commit atomically.

## Run

```bash
mix test
```

## ACP (Zed / Custom Clients)

Run the local ACP stdio server:

```bash
mix cantrip.acp
```

Zed custom agent example:

```json
{
  "agent_servers": {
    "cantrip-ex": {
      "type": "custom",
      "command": "mix",
      "args": ["cantrip.acp"],
      "cwd": "/absolute/path/to/cantrip-ex"
    }
  }
}
```

Protocol implemented: `initialize`, `session/new`, `session/prompt` over JSON-RPC stdio.

## Pattern Agents (01..16)

List available pattern agents:

```bash
mix cantrip.example list
```

Run a pattern by id:

```bash
mix cantrip.example 08
```

Run a pattern with real crystal from env:

```bash
mix cantrip.example 08 --real
```

Pattern `06` uses env-backed real crystal configuration; others default to deterministic fake crystals unless overridden in code/tests.

## Real Crystals (.env)

You can run with real providers (or local OpenAI-compatible servers) via env vars.

Example `.env`:

```bash
CANTRIP_CRYSTAL_PROVIDER=openai_compatible
CANTRIP_MODEL=gpt-4.1-mini
CANTRIP_API_KEY=sk-...
CANTRIP_BASE_URL=https://api.openai.com/v1
CANTRIP_TIMEOUT_MS=30000
```

Then construct with:

```elixir
{:ok, cantrip} =
  Cantrip.new_from_env(
    circle: %{gates: [:done], wards: [%{max_turns: 10}]}
  )
```

`.env` is loaded at app boot for local development.

## Notes for Onboarding

- The runtime threads crystal state through the cantrip value for deterministic fake-crystal tests.
- Code-circle snippets are Elixir (`done.(...)`, `call_agent.(...)`, `compile_and_load.(...)`).
- `FakeCrystal` supports `record_inputs: true` to assert context/tool contracts in tests.
- Current test count: 47 green tests (`mix test`).
