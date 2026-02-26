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
5. Error policy is explicit: expected operational failures become observations; unexpected bugs should crash and be supervised.

### 4) Slice Discipline

1. Implement by slices/milestones defined in `MASTER_PLAN.md`.
2. Treat [`MISSION_CHECKLIST.md`](/Users/deepfates/Hacking/github/deepfates/cantrip-ex/MISSION_CHECKLIST.md) as the current definition of completion.
3. Keep commits atomic and scoped to one slice increment.
4. If a rule is violated, pause and correct before adding new behavior.

### 5) Runtime Safety Requirements

1. Child casts linked via delegation must support parent-linked truncation with reason `parent_terminated` (`COMP-9`).
2. Loom persistence must remain append-only; storage adapters can extend durability but not mutate turn history.
3. Hot-reload (`compile_and_load`) must be warded in production:
   - module allowlist (`allow_compile_modules`)
   - path allowlist (`allow_compile_paths`) when writing files
   - optional source integrity allowlist (`allow_compile_sha256`)
   - optional signer allowlist (`allow_compile_signers`)

## Quality Gates

1. `mix verify`
2. Real crystal integration is opt-in and should be exercised whenever provider env is configured.
3. Conformance behavior must remain aligned with `tests.yaml`.
4. Run `./scripts/check_signer_policy.sh` before merge when `compile_and_load` policy or signer config changes.
