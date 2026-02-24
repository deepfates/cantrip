# Cantrip Spec Decisions (Canonicalization)

These decisions are frozen for implementation unless explicitly changed by a follow-up decision record.

## D-001 Merge Conflict Resolution

Scope: `SPEC.md` conflict markers and duplicated section numbering.

Decision:
1. Treat `tests.yaml` behavior as canonical where spec branches conflict.
2. Maintain one Chapter 1 flow with unique section numbers.
3. Keep both cast and invoke concepts, with cast as single-episode execution and invoke as persistent entity lifecycle.

Rationale: Tests are the executable conformance surface.

## D-002 Naming Canon

Decision:
1. Canonical config key: `require_done_tool`.
2. Canonical delegation gates: `call_agent`, `call_agent_batch`.
3. `call_entity` and `call_entity_batch` are accepted aliases only at parsing boundaries, normalized internally to `call_agent*`.

Rationale: Matches current tests and avoids split semantics.

## D-003 Done Semantics

Decision:
1. `done` is the canonical termination gate across all mediums.
2. Code medium may expose `submit_answer(x)` as syntactic sugar that maps to `done(answer: x)`.
3. Execution semantics for one utterance:
   - evaluate gate calls in declaration order,
   - stop immediately after processing `done`,
   - skip all remaining calls in that utterance.

Rationale: Aligns LOOP-3 tests and supports code-medium ergonomics without bifurcating behavior.

## D-004 Text-Only Termination

Decision:
1. If `require_done_tool: false`, text-only response terminates.
2. If `require_done_tool: true`, text-only response does not terminate.
3. Text-only turns still append loom turn records with empty gate observation.

Rationale: Matches LOOP-6 tests and preserves alternation auditability.

## D-005 Observation Canonical Shape

Decision:
1. Canonical gate observation shape:
   - `gate` (string)
   - `args` (map, optional for legacy)
   - `result` (term)
   - `is_error` (boolean)
   - `tool_call_id` (string | nil)
2. Internal adapters may ingest provider-specific shapes and normalize to this form before loop state update.

Rationale: Removes schema drift across chapters.

## D-006 Retry Semantics

Decision:
1. `max_retries` means additional attempts after the first attempt.
2. Retryable failures do not create additional turns in the loom.
3. Successful retry contributes one final turn record.
4. Failed intermediate retries do not leak into model-visible message history.

Rationale: Required by PROD-2 and prevents training-data distortion.

## D-007 Folding Policy

Decision:
1. Support both triggers:
   - explicit turn threshold (`trigger_after_turns`)
   - token-window threshold policy (default production policy).
2. If both exist, folding triggers when either condition is met.
3. Folding modifies working context only; loom history remains complete.
4. System prompt/call identity is never folded out of first-message position.

Rationale: Reconciles test ergonomics with production policy guidance.

## D-008 Loom Scope and Identity

Decision:
1. Loom is unified per cantrip execution tree (parent + child subtrees).
2. Turn IDs are unique within loom scope.
3. Entity IDs are unique within runtime process lifetime.
4. Parent/child linkage is explicit via `parent_id` and spawning-turn references.

Rationale: Needed for composition auditing and fork semantics.

## D-009 Ward Resolution

Decision:
1. Numeric constraints resolve to most restrictive value.
2. Boolean constraints resolve by logical OR for restrictions.
3. At `max_depth: 0`, delegation gates are removed structurally from child circle.

Rationale: Matches PATTERNS guidance and COMP depth tests.

## D-010 Ephemeral Gate Projection

Decision:
1. Full ephemeral results are stored in loom observation.
2. Model-visible context receives a compact placeholder instead of full payload.
3. Placeholder format: `[ephemeral:<gate_name>]`.

Rationale: Required by PROD-5 and deterministic for tests.

## D-011 Error Handling Model (OTP + Cantrip)

Decision:
1. Expected operational failures (gate failures, provider rate limits, child task failures) are represented as observations with `is_error: true` and remain in-loop.
2. Crystal/provider retries are handled inside one turn and do not emit extra turns (D-006 / PROD-2).
3. Parent casts are not terminated by child task failure (COMP-8); child failure is returned as gate result.
4. Unexpected runtime bugs (invariants violated, programmer errors) should still fail fast and be surfaced to supervision/logging, not silently converted.
5. "Catch-all" exception handling is discouraged; catches/rescues must be scoped to expected failure boundaries.

Rationale: Preserves cantrip semantics ("error is steering") while remaining intentionally OTP-native about unexpected crashes.
