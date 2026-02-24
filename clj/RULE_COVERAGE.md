# Rule Coverage Matrix

This file tracks practical rule coverage in the current Clojure codebase.

## Sources

1. Spec rules: `SPEC.md`
2. Rule catalog: `tests.yaml`
3. Implemented tests: `test/cantrip/*.clj`

## Family Status

| Family | Status | Notes |
|---|---|---|
| `CANTRIP` | Partial | Core shape/invariants covered; YAML runner scaffold executes `CANTRIP-1` |
| `INTENT` | Partial | Required + basic message positioning covered |
| `ENTITY` | Partial | Unique IDs + persistence basics covered; broader lifecycle still pending |
| `LOOP` | Partial | Termination/truncation basics covered in runtime/circle tests |
| `CRYSTAL` | Partial | Shape, IDs, required tool-choice, linkage covered for fake provider |
| `CALL` | Partial | Context assembly covered; folding policy not implemented yet |
| `CIRCLE` | Partial | Medium presence + gate checks + ordered execution basics covered |
| `COMP` | Missing | No `call_agent`/`call_agent_batch` implementation yet |
| `LOOM` | Partial | Append/extract/reward basics covered; advanced metadata/folding integration pending |
| `PROD` | Partial | ACP continuity + redaction covered; retry/folding/ephemeral/stdio-debug pending |

## Immediate Gaps

1. Full executable interpreter for `tests.yaml` actions/expectations.
2. Composition rule family (`COMP-*`) implementation.
3. Production rules for retry/folding/ephemeral handling.
4. Pattern parity examples (`01-16`) and medium completion (`:code`, `:minecraft`).

## Tracking

Detailed task IDs and completion criteria are in `IMPLEMENTATION_TASKS.md`.
