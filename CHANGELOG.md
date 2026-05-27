# Changelog

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
  every assistant turn across sends. The terminating branch of
  `Cantrip.EntityServer.execute_turn/4` never folded the final assistant
  message into `state.messages`. The next send appended a user message
  to a history that still ended at the prior user message; the model saw
  a stack of users with no record of its own answers and anchored on the
  first prompt.
- Fixed: `Cantrip.Folding.partition/1` only preserved one leading
  `:system` message. `Cantrip.EntityServer.initial_messages/3` emits
  two (identity + capability text). On fold, the capability text dropped
  into the foldable body — over long sessions the entity would silently
  lose its medium physics instructions.
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
