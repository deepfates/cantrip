# Contributing

This project follows strict spec-driven development. These rules are mandatory.

## Workflow Requirements

### 1) Strict Red-Green TDD

1. Do not implement a feature before creating a failing, rule-mapped test.
2. Follow: red (fail) -> green (minimal fix) -> refactor.
3. Include relevant `tests.yaml` rule IDs in test names or comments.

### 2) Literate Engineering

1. Core modules must include `@moduledoc` describing purpose and boundaries.
2. Non-obvious logic must include concise intent comments.
3. Keep architecture decisions versioned in `MASTER_PLAN.md` and `SPEC_DECISIONS.md`.

### 3) Elixir/OTP Idiom First

1. Runtime logic should be process-oriented (`GenServer`, `DynamicSupervisor`) with explicit ownership.
2. Use behaviours for boundary abstractions (e.g. crystal, medium, storage adapters).
3. Avoid ad-hoc evaluator shortcuts in core runtime paths.
4. Code-circle snippets are Elixir executed on the BEAM (`done.(...)`, `call_agent.(...)`), not JS.

### 4) Slice Discipline

1. Implement by slices/milestones defined in `MASTER_PLAN.md`.
2. Keep commits atomic and scoped to one slice increment.
3. If a rule is violated, pause and correct before adding new behavior.

## Quality Gates

1. `mix format`
2. `mix test`
3. Conformance behavior must remain aligned with `tests.yaml`.
