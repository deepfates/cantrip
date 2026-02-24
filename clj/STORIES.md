# Cantrip Clojure Stories

This backlog is the implementation contract for this repo.

Source alignment:

1. Spec rules: `SPEC.md`
2. Pattern progression: `PATTERNS.md` (Examples 01-16)

## Story Format

Each story has:

1. User value
2. Constraints
3. Trade-offs
4. Acceptance criteria
5. Spec/pattern anchors

## Epic A: Core Domain Model

### A1. Cantrip as data

As a developer, I define a cantrip as immutable data (`crystal`, `call`, `circle`) and cast intents against it repeatedly.

Constraints:

1. constructor validation enforces required shape and invariants
2. no runtime mutation of `call`

Trade-offs:

1. stricter upfront validation vs flexibility of late-bound mutation

Acceptance:

1. invalid cantrip construction fails with clear errors
2. repeated casts produce independent entities

Anchors:

1. `CANTRIP-1/2/3`, `CALL-1`, `INTENT-1`
2. patterns `01`, `03`

### A2. Circle as canonical medium map

As a developer, I configure a circle with canonical keys (`medium`, `gates`, `wards`, `dependencies`) and never rely on implementation naming.

Constraints:

1. exactly one `medium` per circle
2. dependencies are construction-time only

Trade-offs:

1. explicit domain shape vs ad-hoc transport-specific tuning

Acceptance:

1. conflicting medium declarations are rejected
2. gate dependencies cannot be injected at invocation

Anchors:

1. `CIRCLE-10`, `CIRCLE-12`
2. patterns `03-05`, `07-09`

## Epic B: Loop Engine

### B1. Deterministic turn alternation

As an operator, I trust that each cast alternates entity utterance and circle observation.

Constraints:

1. one composite observation object per turn
2. all gate results ordered within that observation

Trade-offs:

1. deterministic semantics vs throughput-focused loose ordering

Acceptance:

1. `LOOP-1`, `CIRCLE-7` pass
2. done stops gate execution in current utterance after successful call

Anchors:

1. `LOOP-1/3`, `CIRCLE-7`
2. patterns `01-02`

### B2. Termination/truncation correctness

As an auditor, I can distinguish successful completion from ward-enforced cutoffs.

Constraints:

1. malformed `done` does not terminate
2. truncation always records reason and terminal status

Trade-offs:

1. strict terminal semantics vs permissive “best effort” completion

Acceptance:

1. `LOOP-2/4/6/7` pass
2. loom terminal nodes mark terminated vs truncated correctly

Anchors:

1. `LOOP-*`, `LOOM-7`
2. patterns `02`, `04`

## Epic C: Crystal Portability

### C1. Provider normalization and linkage

As an integrator, I can swap providers without changing loop consumers.

Constraints:

1. normalized crystal response contract
2. strict tool-call/result linkage where provider requires it

Trade-offs:

1. adapter complexity vs portability guarantees

Acceptance:

1. `CRYSTAL-3/4/5/6/7` pass
2. mismatched tool result IDs fail deterministically

Anchors:

1. `CRYSTAL-*`
2. pattern `06`

## Epic D: Loom Continuity

### D1. Append-only execution memory

As a debugging/training user, I can replay any thread from immutable turn history.

Constraints:

1. turns never deleted/rewritten
2. reward annotation is only post-write mutation

Trade-offs:

1. storage growth vs forensic traceability

Acceptance:

1. `LOOM-1/2/3/10` pass
2. fork from turn N preserves root->N path semantics

Anchors:

1. `LOOM-*`
2. patterns `10`, `11`, `16`

### D2. Folding as view, not mutation

As an operator, I can manage context pressure without losing historical truth.

Constraints:

1. folding never mutates call or full loom history
2. trigger policy documented and testable

Trade-offs:

1. token efficiency vs higher implementation complexity

Acceptance:

1. `CALL-5`, `LOOM-5/6`, `PROD-4` pass
2. folded contexts still preserve capability presentation and identity

Anchors:

1. spec chapter 6 and production rules
2. pattern `11`

## Epic E: Composition

### E1. Child entity composition

As a developer, parent entities can delegate work via `call_agent` and `call_agent_batch` while preserving safety and observability.

Constraints:

1. child circle subset of parent
2. depth ward enforcement
3. parent survives child errors

Trade-offs:

1. richer decomposition vs larger runtime graph complexity

Acceptance:

1. `COMP-1..9`, `WARD-1`, `LOOM-8/12` pass
2. batch returns request order under concurrent execution

Anchors:

1. composition chapter
2. patterns `10`, `14`, `15`, `16`

## Epic F: Mediums

### F1. Conversation medium

As a baseline user, tool-calling circles operate with conversation as medium and explicit gate invocation.

Anchors:

1. patterns `07`

### F2. Clojure code medium

As a coding user, entity-authored Clojure runs inside a medium context with host-projected gates and persistent turn state.

Constraints:

1. execution surface is medium-defined and warded
2. runtime remains data-first and compositional

Trade-offs:

1. richer action space vs tighter safety/operational requirements

Acceptance:

1. `CIRCLE-9` and code-medium behavior tests pass
2. host-projected `done` path and gate ordering conform

Anchors:

1. patterns `08`, `12`

### F3. Minecraft medium (Witchcraft)

As a Minecraft user, the entity can inspect and act in-world through Witchcraft APIs as a first-class medium.

Constraints:

1. medium composition must still obey circle/gate/ward model
2. world mutation policies are explicit wards

Trade-offs:

1. direct world agency vs high blast radius of actions

Acceptance:

1. read-only world mode works (`player`, `xyz`, `block`)
2. mutation mode works under ward envelope
3. observations capture world actions and errors

Anchors:

1. patterns `15`, `16` (adapted to Minecraft medium)

## Epic G: Interfaces and Ops

### G1. ACP compatibility and session continuity

As an editor user, ACP clients can initialize, start sessions, prompt, and receive updates with durable session continuity.

Constraints:

1. parser accepts common prompt shapes
2. response/update shape remains ACP-compatible

Trade-offs:

1. permissive input parsing vs strict protocol hygiene

Acceptance:

1. `PROD-6`, `PROD-7` pass
2. transcript fixtures cover happy and error paths

Anchors:

1. pattern `13`

### G2. Redaction and observability

As an operator, I can troubleshoot safely without leaking credentials.

Constraints:

1. default logs and loom exports redact secrets
2. explicit debug mode exists for stdio lifecycle and wire traces

Trade-offs:

1. deeper diagnostics vs higher risk of leaking sensitive data

Acceptance:

1. `PROD-8`, `PROD-9` pass (or `PROD-9` documented where test harness cannot enforce)

Anchors:

1. production chapter

## Epic H: Pattern Parity (01-16)

As a learner/operator, I can run examples that demonstrate each pattern in `PATTERNS.md` in Clojure.

Acceptance:

1. examples `01` through `16` exist and run
2. each example has a short note linking to the corresponding spec rules
3. at least one capstone path exercises ACP + composition + persistent loom

## Delivery Order

1. Epics A-C (domain + loop + crystals)
2. Epics D-E (loom + composition)
3. Epic F (`:conversation` then `:code`)
4. Epic G (ACP + redaction)
5. Epic H patterns `01-14`
6. Epic F3 Minecraft medium
7. Epic H patterns `15-16` adapted to Minecraft-capable composition
