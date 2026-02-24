# Cantrip Clojure Implementation Tasks

Status legend: `TODO` | `IN_PROGRESS` | `BLOCKED` | `DONE`

## Current Baseline

1. Core runtime + ACP + redaction implemented.
2. `make conformance` passes current Clojure tests.
3. `tests.yaml` is preflighted, not behaviorally executed yet.

## Phase 0: Tracking + Harness Truth

| ID | Task | Status | Done Criteria |
|---|---|---|---|
| P0-1 | Keep this file as source of truth; update per commit | IN_PROGRESS | Every merged commit updates status here |
| P0-2 | Rename/clarify `make conformance` semantics | DONE | Command names/docs distinguish preflight vs behavioral conformance |
| P0-3 | Add rule-to-test mapping doc (`rule -> test ns -> gaps`) | DONE | Mapping file exists and is complete for all rule families |

## Phase 1: Real Conformance Runner (`tests.yaml` execution)

| ID | Task | Status | Done Criteria |
|---|---|---|---|
| P1-1 | Build YAML-driven runner scaffold | DONE | Runner loads `tests.yaml` and executes at least one rule end-to-end |
| P1-2 | Implement setup/action/expect interpreters | TODO | Runner can execute core loop/crystal/circle/loom/prod scenarios |
| P1-3 | Mark structural-only rules as explicit non-executable | DONE | `skip: true` rules produce clear report output |
| P1-4 | Wire runner into `make conformance` | DONE | `make conformance` includes YAML behavioral execution, not just preflight |

## Phase 2: Domain Normalization + Medium Coherence

| ID | Task | Status | Done Criteria |
|---|---|---|---|
| P2-1 | Create canonical gate normalization path shared by domain/runtime/medium/circle | TODO | No duplicated gate-shape parsing logic remains |
| P2-2 | Normalize capability-view output contract across mediums | TODO | `capability-view` outputs stable, tested shape for map/seq gate defs |
| P2-3 | Add explicit medium protocol ops (`snapshot`, `restore`) | TODO | Medium API supports persistent medium state hooks |

## Phase 3: Production Rules Gaps

| ID | Task | Status | Done Criteria |
|---|---|---|---|
| P3-1 | Retry semantics as single-turn concern (`PROD-2`) | TODO | Retry path represented as one logical turn in loom |
| P3-2 | Cumulative token accounting (`PROD-3`) | TODO | Entity/cast exposes cumulative usage with tests |
| P3-3 | Folding trigger + non-destructive compaction (`PROD-4`) | TODO | Folding policy implemented and tested without data loss |
| P3-4 | Ephemeral observation references (`PROD-5`) | TODO | Working context compacts while loom retains full records |
| P3-5 | Loom export redaction defaults (`PROD-8`) | TODO | Export path redacts secrets by default |
| P3-6 | Stdio lifecycle + debug mode docs (`PROD-9`) | TODO | Documented idle/debug behavior and smoke-tested path |

## Phase 4: Composition

| ID | Task | Status | Done Criteria |
|---|---|---|---|
| P4-1 | Implement `call_agent` | TODO | Parent can spawn child and receive normalized result |
| P4-2 | Implement `call_agent_batch` with stable result ordering | TODO | Concurrent child execution preserves request order |
| P4-3 | Enforce child circle subset + depth wards | TODO | Violations fail deterministically with rule-tagged errors |
| P4-4 | Parent/child loom subtree linkage | TODO | Child root links to spawning parent turn; replay works |

## Phase 5: Mediums + Patterns

| ID | Task | Status | Done Criteria |
|---|---|---|---|
| P5-1 | Implement `:code` medium semantics | TODO | Pattern-equivalent behavior for code medium stories |
| P5-2 | Add runnable examples `01-14` | TODO | Examples exist and run with notes linking rule IDs |
| P5-3 | Implement `:minecraft` medium via Witchcraft bridge | TODO | Read-only + mutation profiles pass acceptance checks |
| P5-4 | Add runnable examples `15-16` adapted to Minecraft composition | TODO | Familiar-style scenario works end-to-end |

## Operating Rules

1. One atomic commit per task ID when possible.
2. Update this file in the same commit as the implementation.
3. No task moves to `DONE` without tests and explicit done criteria met.
