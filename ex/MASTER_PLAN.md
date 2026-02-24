# Cantrip Full Map-Reduce Master Plan

This plan is the reduced output of 21 subagent passes (7 rule slices × 3 lenses: spec-audit, OTP architecture, adversarial tests).

## 1) Forced Decisions Before Coding

These are implementation-blocking ambiguities/contradictions found across `SPEC.md` and `tests.yaml`.

1. Resolve merge conflicts in `SPEC.md` (currently contains conflict markers).
2. Canonicalize naming:
   - `require_done` vs `require_done_tool`
   - `call_entity(_batch)` vs `call_agent(_batch)`
3. Clarify `done` semantics in code medium:
   - explicit gate only, or `submit_answer` projection allowed equivalently.
4. Clarify gate execution semantics with mid-utterance `done`:
   - tests imply: execute in order until `done`, skip after.
5. Clarify folding trigger policy:
   - token-window threshold (spec) vs turn-threshold config (tests).
6. Clarify retry semantics:
   - `max_retries` means additional attempts after first attempt.
7. Clarify loom scope:
   - per-cantrip unified tree (recommended), with optional storage backends.
8. Clarify canonical observation schema:
   - normalize `is_error`, `gate`, `result`, `args`, `tool_call_id?`.

## 2) BEAM/OTP Reference Architecture

### Supervision Tree

```
Cantrip.Application
└── Cantrip.Supervisor (one_for_one)
    ├── Cantrip.Registry            # entity lookup
    ├── Cantrip.Loom.Supervisor     # loom writer + storage
    └── Cantrip.EntitySupervisor    # DynamicSupervisor
         └── Cantrip.EntityServer   # one per cast/invoke
```

### Core Behaviours

1. `Cantrip.Crystal`
   - `query(request) -> {:ok, response} | {:error, reason}`
   - adapters: OpenAI/Anthropic/Gemini/local mock

2. `Cantrip.Circle`
   - gate registry + ward enforcement + medium routing
   - synchronous gate semantics from entity perspective

3. `Cantrip.Medium`
   - `ConversationMedium`
   - `CodeMedium` (real sandbox adapter, not string-pattern evaluator)

4. `Cantrip.Loom.Storage`
   - `MemoryStorage` (tests)
   - `JsonlStorage` or DB adapter (production)

### State Boundaries

1. `EntityServer` owns turn-loop state (`messages`, `turn`, `status`, `depth`, `usage`).
2. `Circle` owns gate execution/runtime medium state.
3. Loom writer owns append-only turn persistence and ID/parent links.
4. Crystal remains stateless across calls.

## 3) Falsification-First Testing Strategy

### Guardrails Against Reward Hacking

1. Invariants first, happy-path second.
2. Test negative paths for every rule family.
3. Assert internal observability properties, not only final answers.
4. Add anti-cheat checks:
   - no post-`done` side-effects
   - no hidden turn increments from retries
   - no ephemeral payload leakage to next prompt
   - child context cannot read parent runtime state
   - append-only loom (except reward annotation)

### Property/Metamorphic Layer

1. Reordering independent child completions does not change batch result order.
2. Fork at turn `N` excludes effects from turns `> N`.
3. Folding changes working context size, not loom history cardinality.
4. Re-run same cast with deterministic crystal yields identical turn trajectory.

## 4) Implementation Slices (Strict Order)

### M0: Spec Canonicalization (Gate Before Any Code)

Scope:
1. Freeze all ambiguities in [`SPEC_DECISIONS.md`](./SPEC_DECISIONS.md).
2. Resolve merge markers / naming aliases at implementation boundaries.
3. Ensure planned tests refer to canonical internal names.

Exit criteria:
1. Decision file accepted and versioned.
2. No unresolved semantic blockers remain.
3. Red test queue for M1 is deterministic.

### M1: Stateless Primitives (Config + Crystal Contract)

Rules: `CANTRIP` construction validation subset, `CRYSTAL-*` core contract

Build:
1. `Cantrip.Config` structs (`Call`, `Circle`, `Ward`, `Retry`, `Folding`).
2. Constructor validation invariants.
3. Crystal behaviour + mock/provider normalization.
4. Response contract checks (non-empty, unique tool_call IDs).

Exit criteria:
1. Config and crystal unit tests pass with no runtime loop dependency.
2. No retry policy in crystal adapter path (retry stays runtime concern).

### M2: Core Loop Runtime

Rules: `CANTRIP-*`, `INTENT-*`, `LOOP-*`, `CIRCLE-1/2`, `ENTITY-2/4`

Build:
1. `EntityServer` loop alternation + termination/truncation.
2. Synchronous ordered gate execution up to `done`.
3. Call immutability + system prompt ordering in loop context.
4. Loom append-only write per turn.

Exit criteria:
1. Single-entity conversation casts satisfy LOOP/CALL/INTENT core tests.
2. Retry attempts do not exist yet in behavior surface.

### M3: Loom Tree Primitives

Build:
1. Parent/child turn linkage model.
2. Fork from turn `N`.
3. Thread extraction API.
4. Metadata completeness contracts.

Exit criteria:
1. Loom guarantees needed for composition are implemented first.
2. Fork and extraction invariants are green.

### M4: Circle Runtime Extensions

Build:
1. tools derived from circle definitions.
2. error observation path.
3. dependency-injected gates.
4. code-medium integration via real medium adapter (no pattern evaluator).

Exit criteria:
1. CIRCLE-3..10 behavior is green in conversation + code medium paths.

### M5: Composition and Delegation

Rules: `COMP-*` + related loom tree rules

Build:
1. `call_agent` / `call_agent_batch`.
2. child gate subset enforcement.
3. depth ward decrement/removal.
4. child crystal override.
5. parent blocking semantics.
6. child errors returned to parent without parent termination.

Exit criteria:
1. Composition works on top of established loom tree primitives.
2. Batch ordering and depth limits verified under concurrency.

### M6: Production Semantics

Rules: `PROD-2/3/4/5` (PROD-1 is design-level)

Build:
1. retry appears as single turn.
2. cumulative token accounting.
3. automatic folding trigger policy (token + turn thresholds per decisions).
4. ephemeral gate projection (context redaction + loom retention).

Exit criteria:
1. Production rules green without corrupting turn accounting.
2. Folding and ephemeral handling preserve loom completeness.

## 5) Risk Register

1. **Spec conflict risk**: unresolved merge markers can create wrong conformance targets.
2. **Architecture drift risk**: shortcut evaluators can pass tests while violating medium model.
3. **Overfitting risk**: brittle tests tied to one mock format instead of behaviour contract.
4. **Concurrency risk**: composition + loom ordering bugs under parallel child execution.
5. **Persistence risk**: loom consistency under crashes/restarts if storage semantics are underspecified.

## 6) Definition of Done

1. All non-skipped rules in `tests.yaml` are green.
2. No string-pattern evaluator in core runtime path.
3. OTP process boundaries and behaviour contracts documented.
4. Each slice merged only after red->green->refactor cycle with atomic commits.
