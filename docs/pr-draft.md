# Familiar production-grade: substrate + persistence + paradigm

This PR makes the Elixir Familiar a long-lived, persistent companion
entity that actually fulfills the framework's claims about itself —
not a demo of pattern 16 but a working pattern 16 entity.

## What's the thesis

The cantrip bibliography frames the substrate as more than agent
plumbing: the loom is "the canonical record, debugging trace, training
data, replay buffer"; the harness is "a first-class engineering
discipline"; and per the spike doc, "ACP/REPL/CLI [are] live views
over the same ordered runtime events." The Zed traces in
`scratch/familiar-run-00{1,2}.md` showed the implementation falling
short of those claims in specific, fixable ways:

  - Children crashed when given bare-named filesystem gates
    (`function_clause`/nil-path).
  - Search results returned a string that broke `Enum.*` composition
    (`BitString not Enumerable`).
  - Code-medium bindings vanished across the `done`-call boundary.
  - The "Persistent Loom" half of pattern 16 was never actually built
    — the JSONL silently dropped non-encodable values and no backend
    loaded on init.
  - `--diagnostics` worked only in `--acp` mode; the REPL surface had
    weaker observability than the editor surface.
  - The Familiar's system prompt taught grammar but not paradigm.

This PR closes each gap and verifies the production claim with
evidence appropriate to the layer of the claim.

## What changed, layer by layer

### Gate substrate

- `Cantrip.Gate.spec/1`: a canonical built-in gate registry (single
  source of truth for description / JSON schema / dependency
  requirements / ACP kind). `Medium.Conversation.tool_definitions` and
  `Medium.Code.format_gate_description` both read from it. No more
  dual sources of truth for built-in gate metadata.
- `validate_gate_path/2` rejects nil and empty-string paths with a
  structured `is_error: true` observation (CIRCLE-5 / LOOP-7 defense
  in depth). The same treatment for empty `search` pattern.
- `search` returns a list of `%{path, line, text}` maps, mirroring
  `list_dir`'s list shape. Composable with `Enum.*` directly.

### SpawnFn dependency wiring (CIRCLE-10)

`EntityServer.maybe_call_child` resolves bare child gate names
through `Gate.spec/1` and merges parent dependencies into the
expanded gates. When the Familiar's prompt teaches the LLM to write
`gates: ["read_file"]`, the child now gets a working filesystem gate
rooted in the parent's sandbox.

### Code medium: binding persistence across the done-call boundary

The `done`-throw used to return the *input* binding to `eval_block`'s
catch, dropping any in-turn assignments. Per-statement evaluation in
`eval_block` now preserves the accumulated binding through prior
statements when `done` (or any other control-flow throw) fires. The
natural "compute, then done" pattern works for the first time —
across turns and across sends within a summon (MEDIUM-3).

### Loom: actually persistent

Two distinct holes filled together:

1. **Silent encoding failures**. The JSONL backend silently dropped
   turns whose values weren't directly Jason-encodable (tuples,
   atoms-as-values, functions, structs). Tagged tuples/atoms now
   round-trip via `__t__` / `__a__` markers; unrestorable values
   (functions, PIDs, refs, ports) survive as visible
   `__inspect__` placeholders. Pattern-15 / -16 substance now
   reaches disk.
2. **No load-on-init across all backends**. Added an optional
   `load/1` callback to `Cantrip.Loom.Storage`. JSONL, DETS, and
   Mnesia all implement it. `Loom.new` calls it after `init`,
   populating `events` and `turns` from durable state. A Familiar
   summoned a second time against the same `loom_path` sees its
   prior turns via `loom.turns` — pattern 16 is real for the first
   time.

   `code_state.binding` round-trips faithfully: tuples back to
   tuples, atoms back to atoms (via `String.to_existing_atom`,
   safe), keyword-list keys promoted via `String.to_atom` at the
   bounded binding-key position. An entity in session 2 calls
   `Keyword.get(binding, :variable_name)` and gets the same value
   session 1 wrote.

   **Documented limit**: atom-keyed maps *inside* user values (the
   entity returns `done.(%{token: "mango"})` and the map has atom
   keys) round-trip with string keys cross-session. Workaround:
   entities use `m["key"]` for cross-session reads of arbitrary
   user maps. The trade-off vs. invasively tagging every map's
   keys is captured in `Cantrip.Loom`'s moduledoc.

### Diagnostics symmetry

`mix cantrip.familiar --diagnostics` now starts the distributed
Erlang node regardless of mode (REPL / single-shot / ACP). Same
remsh-attach affordance across surfaces.

`parse_args/1` extracted as pure routing function; tests pin the
mode-agnosticism of `--diagnostics`.

### Familiar prompt: paradigm, not job description

The prior prompt opened with a job description ("you are a persistent
entity that observes a codebase and orchestrates work") and split
work into pre-classified "casual" vs "real" buckets. The new prompt
leans into the operative naming the bibliography requires
("precise naming is itself part of practice"): the entity is a
*long-lived companion spirit* attached to the codebase; `cantrip.()`
is *summoning a helper*, `cast` is *speaking intent into the circle*,
`dispose` is *letting them disperse*. The loom is *the woven record
of every turn*. Helpers inhabit drawn circles bounded by gates and
wards. Wards aren't restrictions to obey — they're capability
containment.

The prompt removes pre-classification ("depth follows the question"),
blesses introspection (`binding() |> Keyword.keys()`, `loom.turns`),
and condenses the footguns into "the grain of this medium." Verified
interactively against a live model: substantively richer engagement,
operative-name-aware reflection.

### Examples 15 / 16 + behavior ladder

`Cantrip.Examples.run_15` (research fanout) and `run_16` (Familiar
coordinator with persistent loom + filesystem children) added as
FakeLLM-scripted demos using the production `Cantrip.Familiar.new`.
Pattern 12's catalog title corrected to "Persistent Coordinator:
Direct call_entity Delegation" so it doesn't falsely imply the
Familiar pattern.

Behavior ladder gains L4 (single child reads a file in the parent's
sandbox), L5 (parallel `cast_batch` fanout), L9 (cross-session loom
recall after summon → kill → resume).

## What's verified, at what layer

| Claim                                          | Layer                  | Evidence                                                                      |
| ---------------------------------------------- | ---------------------- | ----------------------------------------------------------------------------- |
| Gate calls don't crash on bad args             | Substrate (unit)       | `gate_validation_test`, `spawn_fn_test`                                       |
| SpawnFn wires parent deps into bare child gates | Substrate (unit + int) | `spawn_fn_test` (3 cases) + L4/L5 ladder + real-LLM integration               |
| Bindings persist across the done-call boundary | Substrate (unit)       | `code_medium_ergonomics_test` "binding persistence across the done boundary" |
| Loom captures full turns through JSONL         | Substrate (unit + prop) | `loom_jsonl_persistence_test` + `loom_jsonl_property_test` (StreamData)      |
| Loom rehydrates faithfully on next summon      | Substrate (unit + int) | `loom_jsonl_persistence_test` "cross-session" + L9 ladder                     |
| DETS and Mnesia have same persistence behavior | Substrate (unit)       | `loom_backend_symmetry_test`                                                  |
| `--diagnostics` works in all modes             | Substrate (unit)       | `mix_cantrip_familiar_test`                                                   |
| Pattern 15 / 16 work end-to-end (FakeLLM)      | Integration (scripted)  | `examples_test` + `familiar_behavior_test` L4 / L5 / L9                       |
| The original Zed-trace prompts now flow cleanly | Integration (real LLM) | `zed_trace_replay_test` (3 scenarios)                                         |
| Real-LLM scenarios pass under model variance   | Integration (real LLM) | `familiar_real_llm_multi_seed_test` (≥2/3 over 3 runs each)                  |
| Familiar prompt teaches the paradigm           | Iterative              | One interactive trial; multi-seed eval is V1.5 work                          |

The bottom row is the soft spot. The prompt has been trialed against
one model in one interactive multi-turn session; the engagement was
substantively richer than the prior prompt's behavior, but a real
prompt eval (varied tasks, multiple seeds, rubric-based scoring) is
its own engagement and is properly deferred. The substrate-level
claims are evidence-backed; the prompt-level claim is iterative.

## Deliberately deferred

- Full atom-key round-trip for arbitrary user-value maps. Workaround
  bounded; documented in `Cantrip.Loom` moduledoc.
- DGM-style candidate transactions, lineage projections, artifact
  store. Per the SPIKE doc, these are V1.5 work and the loom now
  has the durable record they would build on.
- A formal prompt eval harness. Multi-task / multi-seed / rubric-based
  scoring would meaningfully strengthen the prompt's production
  claim. Not blocking the substrate work.
- Behaviour-per-gate refactor. Built-ins are stable enough that flat
  function clauses + `Gate.spec/1` is the right shape for V1.

## Files of interest

- `lib/cantrip/gate.ex` — `Gate.spec/1` registry, `validate_gate_path`
  defense, list-shaped `search`
- `lib/cantrip/entity_server.ex` — `resolve_child_gate` /
  `collect_parent_dependencies` (SpawnFn dep wiring)
- `lib/cantrip/code_medium.ex` — per-statement eval preserving
  binding across `done`-throw
- `lib/cantrip/loom.ex` — `Storage.load/1` rehydration
- `lib/cantrip/loom/storage/{jsonl,dets,mnesia}.ex` — symmetric
  `load/1` implementations
- `lib/cantrip/familiar.ex` — paradigm-teaching system prompt
- `lib/cantrip/examples.ex` — `run_15` / `run_16`
- `lib/mix/tasks/cantrip.familiar.ex` — `parse_args/1` extraction,
  mode-agnostic `--diagnostics`

## Verification

- Full suite: 478 tests + 2 properties, 0 failures
- Real-LLM integration (gated): 7 tests across 3 files, all green
  against a live Claude model (~5 minutes total wall clock)
- Format / `--warnings-as-errors` / Credo: clean
- Multi-seed stability: 5 seeds checked, all green
