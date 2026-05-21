# Elixir-Native Runtime Spike

This spike names the runtime boundaries that are currently compressed into
`Cantrip.EntityServer` and `Cantrip.Circle`.

The original goal is still the delivery boundary: make the Elixir
Cantrip/Familiar runtime solid, idiomatic, and reliable enough to carry the
original spirit on the BEAM.

The DGM/Hyperagents framing is useful as a north star, but it should not inflate
the first deliverable. For this spike, it mostly clarifies the cutover order:
the loom should become the durable runtime spine first, and the other boundaries
should hang from ordered loom/runtime events.

The goal is still a reviewable path, but the center is now clearer:

> Cantrip is a supervised BEAM runtime for entities whose durable reality is the
> loom. The solid V1 should make turns, tool calls, child delegation, streaming,
> diagnostics, and protocol edges trustworthy. Evaluation, self-modification,
> generated artifacts, and promotion are staged follow-ons.

## Proposed Boundaries

| Concern | Spike Module | Shape |
| --- | --- | --- |
| Medium physics | `Cantrip.Medium` | Behaviour |
| Medium lookup | `Cantrip.Medium.Registry` | Pure lookup |
| Code medium | `Cantrip.Medium.Code` | Behaviour adapter |
| Bash medium | `Cantrip.Medium.Bash` | Behaviour adapter |
| Conversation medium | `Cantrip.Medium.Conversation` | Behaviour adapter |
| Ward resolution | `Cantrip.WardPolicy` | Pure policy module |
| Gate execution | `Cantrip.Gate.Executor` | Ordered tool-call transaction |
| Turn preparation | `Cantrip.Turn` | Cognitive transaction boundary |
| Provider call | `Cantrip.ProviderCall` | Retry/timing/response boundary |
| Runtime events | `Cantrip.Event` | Versioned event envelope |

## Direction

The next refactor can still move one responsibility at a time:

1. Replace direct `Circle.tool_view/1` calls with `Medium.Registry.present/2`.
2. Move code/bash execution dispatch out of `EntityServer` and through
   `Cantrip.Medium.execute/3`.
3. Move ward query helpers from `Circle` into `WardPolicy`, leaving wrappers for
   compatibility.
4. Introduce a single internal event path consumed by loom, telemetry, CLI, and
   ACP.

However, the cutover should prioritize event/loom correctness before deeper
runtime decomposition. A "single sender" must be mechanically true on the BEAM,
not just an architectural comment.

## North Star

The archive should be a projection of the loom, not a competing persistence
concept.

| Concept | Runtime Meaning |
| --- | --- |
| Loom | Canonical append-only history of what happened |
| Turn | Compatibility projection over `:turn` loom events |
| Entity version | Versioned artifact referenced by loom events |
| Archive | Lineage/evaluation projection over loom events |
| Familiar | The currently promoted live entity version |
| Self-modification | Supervised transaction that creates and evaluates a child version |
| Promotion | Loom-recorded switch from one version to another |

This keeps the existing mythology intact while making self-modification
concrete: a live process does not casually rewrite itself in place. It proposes
new versioned artifacts, evaluates them in an isolated child runtime, records
the outcome, and only then promotes or rejects them.

## Cutover Plan

### Delivery Boundary

Solid V1 is the original upgrade target:

- Elixir-native Familiar runtime.
- Mechanically ordered runtime events.
- Loom event-log compatibility while preserving turn APIs.
- Medium and ward boundaries extracted from the largest runtime modules.
- Stable ACP and CLI projections over Cantrip-shaped events.
- Safe, opt-in diagnostics.
- Fast green tests and a reviewable PR.

V1.5 and later work may build on this substrate:

- Loom lineage/evaluation/artifact projections.
- Artifact store.
- Manual candidate-version transaction.
- LiveView workbench.
- Agent-proposed candidate changes.
- DGM-style autonomous evolution.

Do not smuggle V1.5/V2 work into Solid V1 unless it is needed to make the
runtime spine coherent.

### Current Status

First cuts are in place for the runtime spine:

- Medium presentation and code/bash execution now route through
  `Cantrip.Medium.*` boundaries.
- Ward query and composition helpers now route through `Cantrip.WardPolicy`.
- Ordered conversation tool-call execution now routes through
  `Cantrip.Gate.Executor`.
- Provider invocation and retry now route through `Cantrip.ProviderCall`.
- `Cantrip.Turn.prepare_request/1` owns message folding and medium
  presentation for one provider request.
- Streamed LLM deltas use the runtime event callback path instead of an
  intermediate relay process.
- Runtime events now carry envelope version, sequence, entity id, turn id,
  correlation id, timestamp, depth, and medium.
- The loom now supports `append_event/2`, with `append_turn/2` preserved as a
  compatibility API over `:turn` events.
- Follow-on evolution vocabulary remains in this planning document for V1.5
  rather than in the Solid V1 runtime API.
- ACP bridge lifecycle, timeout fallback, diagnostics opt-in, random diagnostic
  cookies, and last-answer redaction have first-pass fixes.
- Solid V1 landed on `main` via PR #5. The review-leftover cleanup addresses
  gate observation accumulation, ACP answer normalization, deterministic tool
  order, and non-streaming timeout delivery.

The next step is not to add UI or autonomy. After review-leftover cleanup lands,
take only small Solid V1 hardening slices from this document.

### Phase 1: Make Runtime Events Mechanically Ordered

- Replace the current split path where streamed LLM text deltas can arrive from
  a relay process while tool/final events arrive from `EntityServer`.
- Prefer synchronous adapter callbacks for streamed deltas so the entity's
  runtime event order reflects the actual execution order.
- Add sequence and correlation metadata at the canonical event boundary.
- Keep ACP, CLI, telemetry, and tests as projections/subscribers.

This phase closes the most important review risk: if the event order is not
trustworthy, the loom cannot become the durable truth.

### Phase 2: Generalize Loom From Turns to Events

- Add `Cantrip.Loom.append_event/2`.
- Store `:turn` as one event type while preserving `append_turn/2`.
- Extend storage behaviour from turn/reward-specific callbacks toward event
  callbacks, with compatibility shims for existing JSONL/DETS/Mnesia tests.
- Add projections for `turns`, threads, and rewards rather than making them the
  only loom-native shapes.

### Phase 3: Add Entity Version and Artifact Events (V1.5)

- Introduce loom event types for candidate creation, artifact hashing,
  evaluation start/finish, rejection, and promotion.
- Keep generated code and prompt/circle/ward changes as versioned artifacts
  referenced by ids or content hashes.
- Do not hot-swap arbitrary modules as the first self-modification mechanism.

Status: deferred. Solid V1 keeps only generic loom event append/read behavior.

Deferred triage:

1. Add `Cantrip.Loom.LineageProjection` for parent/child entity version ancestry.
2. Add `Cantrip.Loom.EvaluationProjection` for evaluation status and scores.
3. Add a tiny `Cantrip.ArtifactStore` behaviour with a local filesystem backend.
4. Record artifact hashes through loom events, not by embedding large artifact
   bodies in the loom.

### Phase 4: Move Self-Modification Into a Supervised Transaction (V1.5/V2)

- Select a parent entity version from the archive projection.
- Spawn an isolated child runtime/workspace.
- Let the child propose a patch or artifact change.
- Compile, test, evaluate, and record the result.
- Promote only via an explicit loom event.

Deferred triage:

1. Define a `Cantrip.Evolution.Candidate` struct:
   parent version, proposed artifact ids, evaluation id, status.
2. Implement a non-LLM smoke transaction that creates a child version event,
   records one artifact, runs a fixed evaluation command, and records pass/fail.
3. Only after that, let an entity propose a candidate transaction.

### Phase 5: Harden Protocol and Diagnostics Around the Spine

- Make diagnostics opt-in, redacted, and non-authoritative.
- Remove fixed distributed Erlang cookies.
- Tie ACP bridges to owner/session lifetimes.
- Never direct-send duplicate final answers after a bridge timeout.
- Treat ACP/Zed/CLI as live views over the same ordered runtime events.

Status: first-pass ACP/diagnostic hardening is in place.

Remaining triage:

1. Add sequence/correlation metadata at the canonical event boundary.
2. Make ACP, CLI, and future LiveView rendering consume the same internal event
   shape.
3. Keep diagnostics non-authoritative: they inspect runtime state but do not
   become the source of truth.

### Phase 6: LiveView Workbench After the Spine Exists (V2)

LiveView should become the native BEAM interface, but it should not lead the
architecture. It should subscribe to the same runtime/loom projections ACP and
CLI see.

First LiveView surfaces, in order:

1. Loom timeline for one entity.
2. Live entity console with streamed events.
3. Lineage tree from `LineageProjection`.
4. Evaluation dashboard from `EvaluationProjection`.
5. Artifact diff viewer.
6. Promotion/rejection controls.

Do not build a chat page first. Build an entity workbench.

### Actionable Triage Board

#### P0: Make Solid V1 Reviewable

- Keep review-leftover cleanup small, focused, and mergeable.
- Keep full test suite green after cleanup lands.
- Keep `mix format --check-formatted` green.
- Treat any new review thread on the active Solid V1 cleanup PR as the
  immediate next task.

#### P1: Complete The Runtime Spine

- Add event sequence numbers if they are needed to make the current event spine
  mechanically auditable.
- Keep ACP, CLI, and tests consuming Cantrip-shaped events rather than
  protocol-shaped runtime state.
- Avoid more runtime decomposition until the current branch is reviewable.

#### P2: First Candidate Transaction

- Implement a deterministic candidate-version transaction without LLM
  involvement.
- Run `mix test`, `mix credo`, and one custom evaluation suite as candidate
  checks.
- Record pass/fail and promotion/rejection in the loom.

#### P3: Workbench Prototype

- Only after P1/P2 have data worth seeing, add a Phoenix/LiveView shell.
- Start with read-only loom/lineage/evaluation views.
- Add control actions later.

## Known Semantic Watchpoints

- Dune sandbox execution is safer but does not exactly match unrestricted
  `done.()` control flow: code after `done.()` may still execute.
- Bash uses `SUBMIT:` as its termination affordance rather than projecting
  normal gates into shell commands.
- Fork currently uses snapshot-style `code_state`; replay hydration is not part
  of this spike.
- Existing loom storage APIs are turn-shaped. Moving to event-shaped storage
  needs compatibility shims so `append_turn/2`, reward annotation, and thread
  extraction remain stable while the model expands.
- Immediate benchmark performance should not be treated as the only archive
  selection signal. HGM-style metaproductivity belongs in a later projection
  once lineage/evaluation events exist.
