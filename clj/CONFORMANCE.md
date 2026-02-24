# Conformance Commands

This repo currently has three layers of conformance checks:

1. `make conformance-preflight`
2. `make conformance-unit`
3. `make conformance-yaml-scaffold`

`make conformance` runs all three in that order.

Optional exploratory command:

1. `make conformance-yaml-batch`

## What Each Command Means

1. `conformance-preflight`
   - Parses `tests.yaml`
   - Reports family counts and skipped test count
   - Does not execute rule behavior

2. `conformance-unit`
   - Runs Clojure test namespaces under `test/cantrip`
   - Validates implemented behavior covered by current unit tests

3. `conformance-yaml-scaffold`
   - Loads `tests.yaml` via `scripts/tests_yaml_to_edn.rb`
   - Executes one end-to-end scaffold rule (`INTENT-1`) through runtime validation
   - Establishes baseline plumbing for full YAML-driven rule execution

4. `conformance-yaml-batch` (optional)
   - Runs a supported subset of YAML action/expectation shapes
   - Reports unsupported rule IDs clearly
   - Intended for iterative expansion toward full YAML execution

## Current Truth

1. Full `tests.yaml` behavioral execution is not complete yet.
2. YAML execution scaffolding exists and is wired into `make conformance`.
3. Remaining implementation is tracked in `IMPLEMENTATION_TASKS.md` under Phase 1 (`P1-2`, `P1-3`, `P1-4`).
