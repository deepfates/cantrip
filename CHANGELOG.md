# Changelog

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

**Feature roadmap, not cleanup blockers:**

- #8 and #10 (eval harness, distributed Familiar) remain open and labeled
  `feature`.

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
