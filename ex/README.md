# Cantrip (Elixir)

Spec-first implementation of the Cantrip loop in idiomatic Elixir, developed in red-green TDD from API boundaries inward.

## Current Scope

Implemented slice (green):

- Cantrip construction and validation (`CANTRIP-1`, `CIRCLE-1`, `LOOP-2` subset)
- Intent handling (`INTENT-1`, `INTENT-2`)
- Core turn loop (`LOOP-3`, `LOOP-4`, `LOOP-6`)
- Crystal response validation (`CRYSTAL-3`, `CRYSTAL-4`)
- Basic circle gate/ward execution (`CIRCLE-6` subset)
- Loom append-only + reward annotation (`LOOM-3` subset)
- Cumulative usage tracking (`PROD-3` subset)

Pending major areas:

- Composition (`call_agent`, batch, depth recursion)
- Forking/folding semantics
- Code-circle execution medium
- Production retry semantics

## Architecture

Core modules:

- `Cantrip`: public API and loop runtime
- `Cantrip.Call`: immutable call configuration
- `Cantrip.Circle`: gate and ward model + execution semantics
- `Cantrip.Loom`: append-only turn storage
- `Cantrip.Crystal`: crystal adapter behavior
- `Cantrip.FakeCrystal`: deterministic scripted crystal for tests

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

Tests are intentionally spec-rule labeled in [`test/cantrip_core_test.exs`](/Users/deepfates/Hacking/github/deepfates/cantrip-ex/test/cantrip_core_test.exs), so onboarding engineers can trace behavior directly to the spec.

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

## Notes for Onboarding

- The runtime currently threads crystal state through the cantrip value for deterministic testing.
- The loom is append-only by API, with mutation limited to reward annotation.
- `FakeCrystal` supports `record_inputs: true` to assert context/tool contracts in tests.
