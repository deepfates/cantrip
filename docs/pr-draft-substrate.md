# Production-quality Familiar: substrate aligned with the BEAM-native vision

Follow-up to PR #7 (familiar production-grade substrate) addressing
substrate-paradigm misalignment surfaced by actually driving the
Familiar interactively, re-reading the SPEC, and being honest about
what "production" means for an entity that lives in the BEAM.

## The thesis

The cantrip Familiar is "a kind of program that lives in a computer
and uses language to act on everything within it" (A.12, the SPEC's
own words). It reasons in Elixir; it spawns other entities at runtime;
it persists its loom across summons; it can hot-load new code into
its own runtime. **It is BEAM-native**, meaning it shares a runtime
with everything else — the loom storage, the protocol adapter, the
LLM client, the gate executors.

This PR makes the substrate honor that vision.

The previous round of work added real folding and credential
redaction, but it also introduced sandbox-by-default decisions that
fought the paradigm. This round aligns the substrate with the SPEC:

- **Code medium is full Elixir by default.** `binding/0`,
  `try/rescue`, pattern matching, the whole language — they're how
  the entity *reasons in code*, not optional ergonomics. The Dune
  sandbox stays available as `sandbox: :dune` opt-in but is not the
  default.
- **Safety is layered correctly.** Gate root validation in the
  circle, PROD-8 redaction at observations, deployment-level
  isolation as the OS-layer partner. Dune is the last-resort knob for
  hardened-shared-BEAM scenarios — not the default sandbox.
- **The loom defaults to Mnesia** for workspace-attached Familiars.
  BEAM-native, transactional, queryable, distribution-capable.
- **`compile_and_load` is in the Familiar's default gate set**, scoped
  to the `Cantrip.Hot.*` namespace via a new namespace ward. The
  entity can write and load new code into the runtime, supervised by
  BEAM, but cannot redefine framework modules.
- **The prompt teaches the BEAM-native idioms** — pattern matching as
  native control flow, hot reload as evolutionary capacity, the loom
  as queryable shared state.

## What changed

### Substrate

#### Code medium: full Elixir by default

`Cantrip.Familiar.new/1` no longer adds the `:dune` ward by default.
The entity's code medium is unrestricted Elixir. `binding/0`,
`try/rescue`, `Code.ensure_loaded?/1`, and the rest of the language
are first-class. Dune remains available via `sandbox: :dune` for
deployments that specifically need in-process language-level
restriction.

#### Mnesia loom by default for workspace-scoped Familiars

When `:root` is provided to `Cantrip.Familiar.new/1`, the loom
defaults to a Mnesia table derived from the workspace path (sanitized
basename + short hash of full path). Same workspace, multiple summons
→ same table → coherent persistent loom. Distinct workspaces don't
collide.

Explicit overrides honored:

- `loom_path: "/path.jsonl"` — JSONL for portable / exportable traces
- `loom_storage: {:mnesia, [table: :foo]}` / `{:dets, [...]}`/ etc. —
  any backend the user names
- No `:root` + no override — in-memory only (ephemeral; fine for
  tests, not for production)

#### `compile_and_load` in the Familiar's default gates

`compile_and_load` was already a primitive but wasn't in the
Familiar's default circle. Now it is, with the new
`allow_compile_namespaces` ward set to `["Elixir.Cantrip.Hot."]`. The
entity can write new modules under `Cantrip.Hot.*` and hot-load them
into the running BEAM; it cannot redefine `Cantrip.Familiar`,
`Cantrip.Gate`, or other framework modules.

Pairs with BEAM's hot-code-loading semantics and supervised restart:
the entity can try a change and roll back if the change breaks
something. The loom records what was tried; supervision is the safety
net.

New ward type: `%{allow_compile_namespaces: [prefix, ...]}` —
prefix-based module name allowlist for `compile_and_load`. Composes
alongside the existing `allow_compile_modules: [exact_names]` ward.

#### `:loom` is bound in the Dune sandbox

When opted into via `sandbox: :dune`, the loom is now exposed as a
binding in the Dune-sandboxed code medium (LOOM-11), matching the
unrestricted code medium. The prompt teaches `loom.turns`; both
mediums honor it.

#### Familiar composition in the Dune sandbox

Issue #3's core refactor landed in the unrestricted code medium:
prompted Familiar code now uses the public package API directly
(`Cantrip.new`, `Cantrip.cast`, `Cantrip.cast_batch`) instead of a
second `cantrip` / `cast` / `cast_batch` / `dispose` ontology. The
old closures are removed rather than preserved as aliases.

The Dune sandbox is deliberately different at the capability boundary:
Dune restricts remote module calls, including `Cantrip.new/1`. Opt-in
`:dune` users therefore get `done`, `call_entity`, `call_entity_batch`,
the circle's named gates, the `:loom` binding, and `folded_summary`
when folding fires. They do not get the package-module surface unless
a deployment adds an explicit, narrow host adapter for it.

### Folding: §6.8 substance in the sandbox

`Cantrip.Folding.fold/3` now returns `%{messages: [...], summary: ...}`.
The summary text is threaded through `Cantrip.Turn.prepare_request`,
captured on `EntityServer` state, and bound as `folded_summary` in
the entity's eval scope when folding fired this turn. §6.8 says
folding integrates substance into circle state ("variables, data
structures, summaries in the sandbox"); this is the sandbox-state
half.

### Prompt: BEAM-native vocabulary

The Familiar's system prompt now teaches:

- **Pattern matching as native control flow.** `case` over tagged
  gate observations is the recommended branching shape; `if/else`
  isn't Elixir's idiom.
- **`binding/0` for introspection.** Restored as the recommended
  recovery move when the entity loses track of its variables (works
  under unrestricted code medium, the default).
- **`loom.turns` for history walking.** With an example showing
  `Enum.take` + `Enum.flat_map` against the structured turn list.
- **`compile_and_load.(...)` for evolution.** New section "Evolving
  yourself" teaches hot reload as the entity's evolutionary capacity,
  with the namespace boundary and the supervised-rollback model
  named.
- **Medium selection by task shape** (carried over from prior round).
- **The user as a function** (carried over).

### Bridge readability

- `EventBridge.stringify/1` renders maps and lists as readable text
  rather than inspect-form. Bridge feeds the user; the rendering
  should be prose, not Elixir term syntax. (Carried over.)
- ACP runtime familiar drops the per-prompt "Start by listing the
  directory" appendix that was poisoning every response. (Carried
  over.)

### Tests

| Test | What it pins |
| --- | --- |
| `loom_jsonl_persistence_test` + property | JSONL backend round-trips faithfully |
| `loom_backend_symmetry_test` | DETS and Mnesia behave the same |
| `gate_validation_test` | Bad args become observations |
| `redact_test` (11 tests) | PROD-8 patterns work end-to-end |
| `folding_test` (11 tests) | Size-trigger, summary, sandbox binding |
| `code_medium_ergonomics_test` (folded_summary) | `folded_summary` binding visible to entity |
| `m7_hot_reload_test` (new: namespace allow + reject) | Namespace ward enforces module prefix |
| `dune_sandbox_test` | Dune exposes sandbox-safe bindings and documents the module-call boundary |
| `familiar_behavior_test` (new: regression — loom reachability) | `loom.turns` resolvable from default Familiar's eval scope (Zed-trace fix) |

499 tests + 2 properties, 0 failures.

## Safety layered correctly

| Layer | Provides | Limit |
| --- | --- | --- |
| Gate `root` validation | In-circle FS path confinement | Only applies to paths through the gate; raw `File.*` in unrestricted code medium isn't bounded |
| `Cantrip.Redact.scan/1` at gate observation boundary | Credential-shape scrubbing on all gate observations (PROD-8) | Doesn't apply to direct `File.*` (since redaction is in `Gate.execute`) |
| Deployment isolation (container, chroot, ephemeral cwd) | OS-level FS reach of the BEAM process | The framework's responsibility ends here; the operator's begins |
| `sandbox: :dune` (opt-in) | Language-level restriction of `File.*` / `System.*` / `Process.*` / `spawn` / `Code.*` | Costs in-medium expressivity (`binding/0`, `try/1`, etc.); use deliberately. See issue #12 |

Each layer at the right altitude. See `DEPLOYMENT.md` for the full
runbook.

## What's NOT in this PR — tracked durably

Filed as GitHub issues, not "follow-up handwave":

- **Issue #8** — Eval harness for prompt iteration. Multi-task,
  multi-seed, rubric-scored. The methodology piece for measuring
  whether prompt changes actually improve behavior.
- **Issue #9** — First-class `mix` gate for Familiars attached to
  Elixir projects. Argv allowlist, output capture, telemetry.
- **Issue #10** — Distributed Familiar (multi-node, replicated Mnesia
  loom, cross-node casts). The substrate supports it; the cluster
  integration is its own scope.
- **Issue #11** — Full telemetry coverage + observability runbook.
- **Issue #12** — Dune sandbox's in-medium overreach (`binding/0`,
  `try/1`, `Code.ensure_loaded?/1` are restricted but shouldn't be).
  Tracked for whenever someone deploys with `sandbox: :dune` and
  needs full prompt-taught fidelity.

- **Issue #3** (pre-existing) — addressed for the unrestricted
  Familiar path by making in-medium child orchestration use
  `Cantrip.new` / `Cantrip.cast` / `Cantrip.cast_batch` directly.
  The old closures were removed. Dune remains tracked separately
  because its sandbox forbids those module calls by design.

## Files of interest

- `lib/cantrip/familiar.ex` — prompt v5 (BEAM-native vocabulary,
  pattern matching, hot reload) + circle changes (compile_and_load
  in defaults, Mnesia loom default, sandbox opt-in)
- `lib/cantrip/folding.ex` — `fold/3` returns map with summary
- `lib/cantrip/turn.ex` — threads folded_summary out via request map
- `lib/cantrip/entity_server.ex` — captures folded_summary on state,
  exposes via runtime to mediums
- `lib/cantrip/code_medium.ex` — binds `folded_summary` when present
- `lib/cantrip/code_medium/dune_sandbox.ex` — binds `:loom`,
  `folded_summary`, and the lower-level sandbox-safe gate closures
- `lib/cantrip/gate.ex` — `allow_compile_namespaces` ward,
  list_dir bare names, PROD-8 redaction
- `lib/cantrip/redact.ex` — credential-shape patterns
- `lib/cantrip/acp/event_bridge.ex` — readable map/list rendering
- `DEPLOYMENT.md` — production posture guide
- `PR_DRAFT_SUBSTRATE.md` (this file)

## Verification

- Full suite: 499 tests + 2 properties, 0 failures
- Format / `--warnings-as-errors` / Credo (default): clean
- Regression test for the Zed-trace loom-probing failure mode passes
- Hot-reload namespace boundary pinned by tests

## What "production-ready" means here

Not "all tests pass and the docs look nice." It means:

1. **The substrate honors the paradigm.** Code medium is full Elixir,
   gates are the controlled crossings, the circle is the safety
   boundary, the loom is BEAM-native shared state, hot reload is the
   entity's evolutionary surface.
2. **The prompt honors the substrate.** Everything the prompt teaches
   (`binding/0`, `try/rescue`, `loom.turns`, `compile_and_load`,
   pattern matching) actually works in the default posture.
3. **The deployment honors the safety claims.** `DEPLOYMENT.md`
   names the operator's responsibilities (containerization, Mnesia
   storage, network egress, telemetry subscription) so the
   "production-grade" claim has somewhere to land.
4. **The unfinished work is named, not hidden.** Five GitHub issues
   describe what's not here and why it's separate.

When the next change goes in — eval harness, mix gate, distribution —
it'll go in against a substrate that doesn't need to be re-aligned
with the vision first. That's the durable thing this PR delivers.
