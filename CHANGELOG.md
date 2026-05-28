# Changelog

## Unreleased

Nothing yet.

## 1.3.0 - 2026-05-28

Post-v1.2 stabilization release. This drains the hardening work that landed
after `1.2.0` into a real source/package version, including the Bash sandbox
boundary change, runtime and persistence fixes, API surface cleanup, package
metadata fixes, and Familiar composition guidance.

**Breaking:**

- Bash-medium cantrips now require an OS sandbox and fail closed when neither
  `bubblewrap` nor `sandbox-exec` is available. Declared gates are projected
  into the shell as PATH commands and dispatch back through the parent BEAM;
  raw shell remains the medium, but gate authority now comes from the circle
  rather than ambient process access. The `done` gate is exposed as
  `cantrip_done` because `done` is a shell keyword. Tests may opt into
  `medium_opts: %{sandbox: :passthrough}`; production cannot.
- Bash sandbox verification now includes representative shell workloads
  (`git`, `make`, `jq`, `/dev/null` redirects, and common
  `find`/`sed`/`grep` pipelines). The workload suite is the support contract:
  when a real shell workload should be supported, add it there so adapter
  gaps fail in CI instead of surfacing in user sessions. Workload tests opt
  into `%{bash_network: :on}` so GitHub-hosted Linux runners can exercise
  bubblewrap shell behavior even when they cannot create bubblewrap's default
  network-deny namespace; separate tests pin the default network-deny command
  shape.

**New:**

- Familiar prompt/runtime evaluation now has a composition metric:
  `child_medium_used` scores whether a child turn used the expected medium.
  Turn metadata records `medium_type`, JSONL rehydration preserves it, and
  the eval suite contrasts raw data-dump answers with code-gathering plus
  conversation-child synthesis. Evidence: PR #90, issue #83.
- Default Familiar guidance now explicitly teaches answer-shape selection:
  gather and compose in code, then delegate speech-shaped synthesis,
  explanation, review, naming, judgment, decision, or voice to a
  conversation child. Explicit user requests for a child, medium, or batch
  shape are treated as directives unless impossible. Evidence: PR #90,
  issue #83.

**Fixes:**

- Bash sandbox support now has representative shell workload coverage for
  `git`, `make`, `jq`, `/dev/null`, and common `find`/`sed`/`grep` pipelines,
  including the GitHub Actions runner network-namespace constraint. Evidence:
  PR #84, issue #82.
- The Hex package now includes `.env.example`, matching the README quick
  start. Package metadata tests assert README `cp` sources exist and ship in
  the Hex file list. Evidence: PR #88, issue #85.
- The documented public API surface now matches generated docs: internal
  modules are hidden, `docs/public-api.md` names the supported surface, nested
  modules are checked from application metadata, and ExDoc warnings are errors.
  Evidence: PR #89, issue #87.
- Provider and gate boundaries are typed more explicitly: LLM provider
  responses flow through `%Cantrip.LLM.Response{}`, gate arguments are
  normalized through per-gate DTOs, ACP `_meta` overrides are constrained, and
  provider option/usage forwarding has regression coverage. Evidence: PRs
  #57, #66, #76, and #77.
- Durable loom and JSONL behavior is stricter: append semantics align between
  in-memory and durable paths, JSONL writes are serialized, persisted
  code-state bindings are compacted, event upcasting is versioned, and
  truncation/medium metadata rehydrate as atom keys. Evidence: PRs #66, #70,
  #71, #74, and #90.
- Streaming and observability paths preserve context while staying bounded:
  streaming emits real text deltas, ACP trace context is propagated, intent
  telemetry is redacted, streaming delivery has backpressure, bridge delivery
  uses bounded barriers, and early stream halt shuts down runner tasks.
  Evidence: PRs #50, #58, and #75.
- Child composition is more disciplined: pre-built child casts compose parent
  wards, declaration-time child-spawn wards are enforced, and the default
  Familiar can read files through its normal observation gates. Evidence: PRs
  #72, #73, and #78.

**CI / packaging:**

- GitHub Actions checkout was updated for the Node 24 runner environment.
  Evidence: PR #81.
- The cleanup status ledger records the post-v1.2 hardening pass and the CI
  gates that made it durable. Evidence: PR #80.

## 1.2.0

Post-v1 feature completion pass. The two feature-roadmap items left after
the `1.1.0` hardening release are now shipped and closed with proof.

**New:**

- Added a Familiar eval harness for prompt/runtime regression work:
  multi-scenario and multi-seed runs, fixture workspaces, persisted JSONL
  transcripts, JSON reports, rubric criteria, optional judge scoring, and
  `mix cantrip.eval` CI thresholds. Evidence: `test/familiar_eval_test.exs`,
  `test/mix_cantrip_eval_test.exs`, `docs/eval-harness.md`, PR #38.
- Added distributed Familiar support: root and child cantrips can target
  named BEAM nodes through `:node`, remote casts preserve their node handle,
  remote child observations are grafted into the parent loom, and
  `Cantrip.Cluster` provides Mnesia extra-node/table-copy helpers for
  replicated loom storage. Evidence: `test/distributed_cantrip_test.exs`,
  `test/cluster_test.exs`, `docs/distributed-familiar.md`, PR #39.

**Fixes before tag:**

- Remote distributed calls now use bounded `:rpc.call/5` timeouts instead of
  the distributed Erlang default of `:infinity`; unknown string node names fail
  closed instead of silently falling back to local execution.
- `Cantrip.Cluster.connect_mnesia/2` now preserves Mnesia schema timeout
  details so operators can see which table failed to synchronize.

## 1.1.0

Post-v1 hardening and cleanup pass. All cleanup issues from the v1 backlog
are closed with proof, including issues filed during the cleanup pass
(#32, #34, #35, #36, #37). See the cleanup-status tracker for the full ledger.

**Behavior change** worth flagging for downstream callers:

- `compile_and_load` now requires an explicit `allow_compile_modules`
  allowlist; previously an empty allowlist was permissive. Deprecated
  `allow_compile_namespaces` wards fail loudly instead of being silently
  ignored. `Elixir.Cantrip.*` module names are rejected from hot-load
  allowlists (except the explicit `Elixir.Cantrip.Hot.*` namespace).

**Fixes:**

- `EntityServer` no longer runs entity episodes inside the GenServer
  mailbox. Episodes execute in a supervised per-entity runner task and
  reply via `GenServer.reply/2`. Concurrent `send/2` while an episode is
  running returns busy immediately. Code-medium port ownership survives
  across persistent sends. Crash-restore preserves stream context.
- Malformed JSON in provider tool-call arguments now produces a structured
  `is_error: true` observation rather than silently substituting `args: %{}`
  and proceeding to (potentially) the wrong gate execution. Decode failure
  carries `args_raw` + `args_decode_error` from adapter through the executor.
- Mnesia `ensure_schema/0` now propagates non-`already_exists` errors as
  root-cause `init/1` failures; previously the catch-all `:ok` clause
  hid filesystem and permission errors.
- Unknown medium types now fail validation with an explicit error and a
  list of valid options rather than silently normalizing to `:conversation`.
- All `String.to_atom/1` paths from external strings are now bounded:
  parent-context normalization uses a bounded allowlist; code-medium gate
  bindings use `String.to_existing_atom/1`; loom JSONL restoration uses
  existing atoms; Familiar table/node atoms use SHA-256 fingerprints.
- All three filesystem gates (`read_file`, `list_dir`, `search`) now route
  through shared path validation consistently: missing root fails closed,
  path traversal fails closed.
- Code-medium bare gate-call rewriting now parses with
  `Code.string_to_quoted/1` and rewrites local gate-call AST nodes rather
  than doing text-level rewrites. Strings, remote calls, already-dotted
  calls, and definition heads are no longer subject to surprising rewrites.
- Safe boundary formatting wraps provider errors, JSONL persistence fallbacks,
  port code-medium error surfaces, gate observations, ACP wire
  stringification, and CLI output. Credential-shaped substrings are redacted
  before crossing entity, disk, or protocol boundaries.
- `req_llm` 1.12 preserves multiple system messages through both Anthropic
  and Gemini encoders; previously the v1.9 path could drop secondary
  system messages.
- Familiar workspace cookie now fails loudly on invalid existing cookies
  rather than silently regenerating; existing distributed connections are
  no longer at risk of being broken on a malformed-cookie restart.
- The live real-LLM echo/done integration prompt now gives a stricter
  two-step tool contract and descriptions so current Anthropic models
  terminate with `done` instead of looping on `echo`.

**New:**

- Added a first-class `mix` gate for Familiars attached to Elixir workspaces.
  It runs allowlisted Mix tasks under the configured root with argv as data,
  bounded output, timeout handling, and structured observations. The Familiar
  default allows `compile` and `format`; `test` is opt-in with `run_tests: true`
  or an explicit `allow_mix_tasks` override.
- `Cantrip.Familiar.new/1` documented Dune-variant divergence in
  `docs/port-isolated-runtime.md`. `sandbox: :dune` is now explicitly a
  smaller-surface in-process variant of the code medium with different
  bindings — entity prompts need to match the variant in use.
- `test/readme_examples_test.exs` pins the README/public-api quickstart
  shapes; future drift between documented examples and the runtime
  constructor signature fails CI.
- `docs/observability.md` is the canonical telemetry event registry
  (subscription patterns, alert recommendations, trace correlation model);
  implementation of the 9-item event checklist tracked on #11.
- `docs/cleanup-status.md` is the living tracker for the cleanup pass.

## 1.0.0

The first stable release. The Elixir implementation is the canonical
package surface; the runtime is documented and live-verified across
the Anthropic model tier (haiku, sonnet, opus).

Bug fixes surfaced during pre-tag live verification against real
Anthropic. All four shipped past `mix verify` green; all four needed
live driving to surface. Adds a v1 audit document and a live-integration
test module.

- Fixed: streaming responses dropped every tool call. The adapter consumed
  the chunk stream via `tokens/1` + `Enum.reduce` for the realtime text
  delta, then called `tool_calls/1` on the now-depleted stream and got
  nothing. Switched to `ReqLLM.StreamResponse.process_stream/2`, the
  documented public API for streaming tool-using agents.
- Fixed: persistent entities (`Cantrip.summon` + `Cantrip.send`) lost
  every assistant turn across sends. The terminating branch of entity turn
  execution never folded the final assistant message into `state.messages`.
  The next send appended a user message to a history that still ended at the
  prior user message; the model saw a stack of users with no record of its
  own answers and anchored on the first prompt.
- Fixed: folding only preserved one leading `:system` message even though
  initial message construction can emit two (identity + capability text).
  On fold, the capability text dropped into the foldable body — over long
  sessions the entity would silently lose its medium physics instructions.
- Upgraded `req_llm` from `~> 1.9` to `~> 1.12`. v1.12's
  `agentjido/req_llm@9d790fd` removes the offending `intersperse` between
  Anthropic system content blocks. With the upstream encoder fixed, the
  local workaround introduced in c994878 was deleted.
- Added `test/live_anthropic_test.exs` covering code-medium sync,
  code-medium streaming, and conversation-medium tool-calling. Gated on
  `RUN_REAL_LLM_TESTS=1` via existing `Cantrip.Test.RealLLMEnv`.
- Added `docs/v1-audit.md` recording verified paths, uncertain paths,
  and bugs found and fixed during the pre-tag audit.

## 1.0.0-rc.1

- Made the Elixir implementation the only canonical package surface.
- Removed the old spec/conformance scaffold and replaced unique coverage with
  native ExUnit tests.
- Removed the compiled examples module and example Mix task; the notebook and
  tests are the teaching surface.
- Removed hand-written OpenAI-compatible, Anthropic, and Gemini adapters.
  Provider configuration now routes through ReqLLM via `Cantrip.LLM.from_env/1`.
- Removed DETS and Auto loom storage. Supported storage is memory, JSONL, and
  Mnesia.
- Removed `call_entity` and `call_entity_batch` gates. Composition now uses
  `Cantrip.new/1`, `Cantrip.cast/3`, and `Cantrip.cast_batch/2`.
- Removed the bare `read` gate. Use `read_file`, which validates paths against
  the configured root.
- Reduced Mix task surface to `mix cantrip.cast` and `mix cantrip.familiar`.
- Made Familiar ACP the default ACP runtime.
- Made Familiar hot-loading opt-in with `evolve: true`.
- Replaced process/cutover docs with package docs: README, CONTRIBUTING,
  DEPLOYMENT, architecture, signer-key runbook, and changelog.
- Added public API and v1 migration guides to the packaged ExDoc extras.
- Added the safe port code medium. `sandbox: :port` evaluates LLM-written
  Elixir through Dune in a child BEAM process while gates, child cantrip API
  calls, stdio, loom grafting, telemetry, provider access, and hot-load policy
  stay in the parent.
- Added `port_runner` for launching that child through a deployment-provided
  OS/container sandbox.
- Made the Familiar default to the safe port code medium. Raw child-BEAM
  evaluation remains available as `sandbox: :port_unrestricted`; the old
  host-BEAM evaluator remains available as `sandbox: :unrestricted` for
  trusted local development.
- Added `docs/port-isolated-runtime.md` to document the implemented isolation
  boundary and remaining deployment responsibilities.
