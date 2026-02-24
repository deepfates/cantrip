# Clojure Implementation Plan (Full Spec + Full Patterns)

This plan operationalizes:

1. `SPEC.md` as normative behavior
2. `tests.yaml` as conformance harness
3. `PATTERNS.md` examples `01-16` as product-level acceptance trajectory

## 1. Design Principles

1. Data-first domain model for all cantrip nouns.
2. Medium-dispatched behavior by `:medium` value.
3. Compositional transforms over circle/ward/entity data.
4. Pure core loop decisions, effectful edges.
5. Clojure/JVM idiom using canonical cantrip vocabulary in the public API.

## 2. Canonical Public Data Shapes

## 2.1 Cantrip

```clojure
{:crystal {:provider :openai :model "gpt-5-mini" ...}
 :call {:system-prompt "..." :require-done-tool false ...}
 :circle {:medium :conversation
          :gates {:done {...} :echo {...}}
          :wards [{:max-turns 24}]
          :dependencies {...}}
 :runtime {:retry {...} :folding {...}}
 :loom {:storage {:kind :memory}}}
```

## 2.2 Entity State

```clojure
{:entity-id "..."
 :status :running|:terminated|:truncated
 :turn-index 0
 :session-id nil|"..."
 :working-context [...]
 :medium-state {...}
 :cumulative-usage {...}}
```

## 2.3 Observation

Normalized per gate call:

```clojure
{:gate "done"
 :arguments "{...json...}"
 :result "..."
 :is-error false
 :tool-call-id "call_123"|nil}
```

## 3. Runtime Model

## 3.1 Core Namespaces

1. `cantrip.domain` (schemas, validation, normalization)
2. `cantrip.runtime` (loop orchestration)
3. `cantrip.circle` (gate execution + ward envelope)
4. `cantrip.crystal` (provider adapters)
5. `cantrip.loom` (append-only tree + storage)
6. `cantrip.protocol.acp` (stdio ACP router)
7. `cantrip.examples` (patterns `01-16`)

## 3.2 Medium Dispatch

Use protocol + multimethod:

1. protocol for stable operations (`capability-view`, `execute-utterance`, `snapshot`, `restore`)
2. multimethod dispatch on `(:medium circle)` for semantics:
   - `:conversation`
   - `:code`
   - `:minecraft`

## 3.3 Ward Envelope

`resolve-ward-envelope` is pure and compositional:

1. numeric limits: restrictive min
2. booleans: restrictive OR
3. sets/lists: union for exclusions

Applied at:

1. circle construction
2. child composition
3. per-turn preflight checks

## 4. Implementation Milestones

## M0: Rule Lock + Harness Hygiene

1. Ensure all new rules in spec have matching tests in `tests.yaml`.
2. Fix legacy YAML syntax issues so harness parses cleanly.
3. Add `make conformance` target.

Exit:

1. harness parses and executes
2. baseline report shows expected red set

## M1: Domain + Loop Foundations

Build:

1. cantrip construction/validation (`CANTRIP-*`, `CALL-1`, `INTENT-1`)
2. cast loop alternation and terminal semantics (`LOOP-*`)
3. done-failure semantics (`LOOP-7`)

Exit:

1. Chapter 1 tests green

## M2: Crystal Adapters

Build:

1. provider-neutral crystal contract
2. tool call ID checks and linkage rules (`CRYSTAL-4`, `CRYSTAL-7`)
3. required tool-choice behavior (`CRYSTAL-5`)

Exit:

1. Chapter 2 tests green

## M3: Circle + Gates + Wards

Build:

1. gate execution ordering/sync semantics
2. dependency-context injection at construction
3. canonical `medium` requirement (`CIRCLE-12`)

Exit:

1. Chapter 4 tests green

## M4: Loom Core

Build:

1. append-only tree model
2. fork/extract/reward annotation
3. metadata (`tokens`, `duration`, terminal flags)

Exit:

1. Chapter 6 tests green

## M5: Composition

Build:

1. `call_agent`, `call_agent_batch`
2. child subset circles + depth rules
3. parent-child loom subtree linkage

Exit:

1. Chapter 5 tests green

## M6: Production Semantics

Build:

1. retry as single-turn concern
2. folding trigger and non-destructive context compaction
3. ephemeral observations with full loom retention
4. ACP core flow and session continuity (`PROD-6`, `PROD-7`)
5. redaction defaults (`PROD-8`)
6. stdio lifecycle docs/debug affordances (`PROD-9`)

Exit:

1. Chapter 7 tests green

## M7: Code Medium (`:code`)

Build:

1. Clojure code medium with host-projected gates
2. medium state persistence across turns
3. capability view generation for crystal context

Execution surface:

1. local profile for interactive development
2. warded profile for agentic operation

Exit:

1. pattern stories `08`, `12` satisfied

## M8: Pattern Suite `01-16`

Build:

1. examples mapped one-to-one to `PATTERNS.md`
2. smoke tests + scenario fixtures per pattern
3. docs linking each example to spec rule IDs

Exit:

1. all examples runnable
2. pattern acceptance checklist green

## M9: Minecraft Medium (`:minecraft`) via Witchcraft

Build:

1. Witchcraft bridge as medium execution substrate
2. world inspection actions (`player`, `xyz`, `block`) first
3. warded world mutation actions second
4. all observations normalized into loom model

Witchcraft references:

1. plugin + nREPL mode
2. REPL-first operation
3. world APIs under `lambdaisland.witchcraft`

Exit:

1. read-only and mutation profiles both pass acceptance
2. familiar pattern can compose child entities with Minecraft-aware tasks

## 5. Pattern Mapping Table (Implementation)

1. `01-02`: crystal + gate primitives
2. `03-05`: circle invariants + ward envelope
3. `06`: provider portability
4. `07`: conversation medium baseline
5. `08-09`: code + alternate medium semantics
6. `10`: parallel delegation
7. `11`: folding
8. `12`: full code agent
9. `13`: ACP endpoint
10. `14`: recursive delegation + depth envelope
11. `15`: research entity with medium composition
12. `16`: familiar long-lived coordinator + persistent loom

## 6. Testing Strategy

1. Conformance tests from `tests.yaml` are mandatory.
2. Pattern tests validate product semantics, not just rule compliance.
3. ACP transcript fixtures verify protocol interoperability.
4. Medium tests verify capability view + observation normalization.
5. Security tests validate redaction behavior on logs/loom export.

## 7. Delivery Method

Per slice:

1. write failing tests first
2. implement minimal passing behavior
3. run full suite
4. commit atomic change

Operational gates:

1. no merge if conformance regressions
2. no merge if pattern acceptance regresses

## 8. Risks and Mitigations

1. Risk: protocol drift across ACP clients
Mitigation: transcript fixture corpus + parser normalization

2. Risk: medium execution semantics diverge from spec
Mitigation: normalized observation contract + shared runtime assertions

3. Risk: composition complexity causes subtle loom bugs
Mitigation: parent-child subtree invariants + fork replay tests

4. Risk: secret leakage in diagnostics
Mitigation: mandatory redaction pass before log/export writes

5. Risk: Minecraft action blast radius
Mitigation: explicit ward profiles and read-only default

## 9. Definition of Done

1. Spec conformance suite is green.
2. Patterns `01-16` are implemented and runnable.
3. ACP session continuity works with transcript fixtures.
4. Code medium and Minecraft medium both operate under the same circle/ward/loom semantics.
5. Documentation describes domain model in canonical cantrip vocabulary.
