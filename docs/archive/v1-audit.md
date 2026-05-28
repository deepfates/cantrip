# v1.0.0 pre-tag audit

Audit target: branch `feat/v1-final`, after the `req_llm` 1.12 upgrade and the streaming tool-call fix.

This report uses "verified" narrowly: the path was driven locally, covered by an existing live test, or source-traced with a focused regression test. I did not have provider credentials in this sandbox (`RUN_REAL_LLM_TESTS`, `CANTRIP_MODEL`, `CANTRIP_API_KEY`, and common provider keys were absent), so new live-provider checks are listed as uncertain.

## Verified working

### ReqLLM adapter shape and local error paths

Evidence:

- `mix test test/req_llm_adapter_test.exs test/runtime_boundary_spike_test.exs` passed: 54 tests, 0 failures.
- This drives adapter construction, bad-provider/missing-model errors, state preservation on errors, option threading, tool normalization, streaming mode selection, and the `ReqLLM.StreamResponse.process_stream/2` path that reconstructs streamed Anthropic-style tool calls.
- I source-traced `deps/req_llm/lib/req_llm/providers/anthropic/context.ex` from `req_llm` 1.12.0. Its Anthropic system encoder now rejects blank system blocks and returns a bare string for a single text block or a list of real content blocks for multiple system messages. That matches the reason the local workaround could be removed.
- I source-traced `deps/req_llm/lib/req_llm/stream_response.ex`: `process_stream/2` consumes the stream once, invokes result callbacks for content chunks, awaits metadata, and builds a complete `ReqLLM.Response`. That is the correct API for Cantrip's streaming adapter.

Not verified live in this pass:

- Real 429 response shape from Anthropic/OpenAI/compatible providers.
- Real connection drop mid-stream.
- Real malformed provider tool arguments.

### Folding with the real initial two-system shape

Evidence:

- `mix test test/folding_test.exs` passed: 12 tests, 0 failures.
- I added a regression test for the actual initial message shape `system, system, user, ...`.
- I fixed `Cantrip.Folding.partition/1` so folding preserves all leading system messages plus the first user intent, rather than preserving only `system, user`.

Impact:

- Before this fix, a Familiar/code/bash prompt with both identity text and medium capability text could fold the second system message into the summarized middle. That meant folding could silently remove medium physics/tool instructions from the prompt view.
- After the fix, identity, capability text, and original intent stay pinned ahead of the folded summary.

### Code, conversation, and bash local medium paths

Evidence:

- `mix test test/bash_medium_test.exs test/summon_test.exs test/composition_test.exs test/spawn_fn_test.exs` passed: 26 tests, 0 failures.
- `:bash` was driven through `Cantrip.cast/3` with `FakeLLM` tool calls, including a two-turn command then `SUBMIT:` completion.
- Multi-send persistent entity behavior was driven through `Cantrip.summon/1`, `Cantrip.summon/2`, and `Cantrip.send/2`.
- Child cantrip creation and child LLM inheritance were driven through code-medium parent execution, including a child reading from the inherited filesystem root and returning a result.

Ground-truth limit:

- These are harness and runtime checks with deterministic `FakeLLM`, not real-provider checks. They prove Cantrip's loop, loom, medium dispatch, gate execution, and child wiring behave for production-shaped responses emitted by the local fake.

### Mix task construction logic

Evidence:

- `mix test test/mix_cantrip_familiar_test.exs` passed: 17 tests, 0 failures.
- This verifies `mix cantrip.familiar` argument routing, diagnostics routing, `--loom-path` policy, workspace-stable node naming, and `build_familiar/1` option threading.

Not verified:

- Direct execution of `mix cantrip.cast` in this sandbox. The Mix process failed before task code ran because Mix 1.19 attempted to start `Mix.PubSub` and could not open a TCP socket under sandbox policy (`:eperm`). This is an environment limitation, not evidence about task behavior.

## Uncertain / worth verifying live before tag

### Provider error responses through `Cantrip.LLMs.ReqLLM`

Drive these with real providers:

- Anthropic 429/rate-limit response through sync mode.
- Anthropic 429/rate-limit response through streaming mode.
- A wrong API key / auth failure for the configured release provider.
- A mid-stream network close or timeout, if practical with a local proxy or very low receive timeout.

Expected evidence:

- `Cantrip.cast/3` should return `{:error, message, cantrip}` without crashing the entity process.
- Error metadata should retain useful provider status/message details where `ReqLLM` supplies them.
- Streaming requests should not retry after partial event emission; `Cantrip.ProviderCall.retry_allowed?/1` intentionally disables retries when `emit_event` is present.

### Malformed JSON tool arguments from a provider

Current behavior:

- `Cantrip.LLMs.ReqLLM.normalize_tool_calls/1` decodes binary arguments with `Jason.decode/1`.
- If decoding fails, it silently falls back to `%{}`.

Why this is uncertain:

- Local code inspection shows the raw malformed argument string is lost before the gate layer sees it.
- For required-arg gates this usually becomes a structured missing-argument observation, so the loop may recover.
- For optional-arg gates it could execute with defaults, which may hide a provider/tool-call encoding problem.

Drive live or with a provider fixture before tagging:

- Force or fixture a tool call whose arguments are invalid JSON, then verify whether Cantrip should continue with a gate-level observation or fail the provider call.
- I did not change this behavior because it is a product/contract decision, not a small mechanical bug.

### Live `:bash` medium

Local status:

- Bash medium execution works through `FakeLLM`.

Live check to run:

- Configure the real release model and run a bash cantrip that must emit a `bash` tool call and finish with `SUBMIT:`.
- Example intent: "Run `pwd`, then submit the basename of the directory."

Why:

- The bash prompt has different medium physics from code/conversation and has not been driven against Anthropic in the described live pass.

### Real multi-turn provider state

Local status:

- Multi-turn/multi-send works with `FakeLLM`.
- Existing gated live replay tests (`test/zed_trace_replay_test.exs`, `test/familiar_real_llm_*`) appear intended to cover real multi-turn behavior when provider env is available.

Live check to run:

- Summon a Familiar against Anthropic with a persistent loom.
- Send at least three prompts to the same pid.
- Confirm the model sees prior context, the loom accumulates intent and turn records under one entity, and folding does not fire before the configured threshold.
- Then lower `folding.trigger_after_turns` or threshold and verify the folded summary appears while both system messages and the original intent remain present.

### Child cantrip with a real provider

Local status:

- Child LLM inheritance and child gate dependency inheritance work with `FakeLLM`.

Live check to run:

- Parent code medium asks a child to read a small file and return a one-line result.
- Verify the child uses the same configured provider/model unless `child_llm` overrides it.
- Verify child turns graft into the parent loom and errors surface as observations, not crashes.

### `mix cantrip.cast`

Local status:

- I could not execute the task directly because the sandbox blocked Mix PubSub TCP setup before task code ran.

Live/local machine check to run outside this sandbox:

- `mix cantrip.cast "say hi" --max-turns 3`
- `mix cantrip.cast --familiar --loom-path .cantrip/audit-cast.jsonl "list one file and report its name"`
- Repeat with `CANTRIP_STREAM=true`.

### `req_llm` 1.12 refactors beyond Anthropic system prompts

Source-traced:

- Anthropic system encoding no longer emits blank separator blocks.
- Streaming response processing still returns reconstructed tool calls.
- The default streaming chunk accumulator preserves arg fragments and falls back to original tool-call args when fragment JSON cannot decode.

Still worth live checking:

- OpenAI-compatible provider with tool calls, because v1.12 includes provider deduplication and DualKeyAccess removal.
- Gemini/Google only if it is in the v1 release support matrix.
- Any provider relying on string-keyed response maps or provider-specific usage metadata.

## Update: items verified live after audit landed

The following items were originally in "Uncertain"; I drove them after codex's audit landed and either confirmed them working or found+fixed real bugs.

### Verified: live `:bash` medium

Driven `mix run` script against `anthropic:claude-haiku-4-5`: model called bash to run `pwd`, extracted the basename, finished with `SUBMIT:`. 2 turns, 1573+114 tokens. The `:bash` medium produces the same two-system shape (identity + capability) as `:code` and goes through the same adapter path.

### Verified: live across the Anthropic model matrix

`test/live_anthropic_test.exs` (code sync, code streaming, conversation tool-calling) was driven against `claude-haiku-4-5`, `claude-sonnet-4-5`, and `claude-opus-4-5` after the rc.2 fixes. All three suites passed with no behavioral differences worth noting:

- haiku-4-5: 3 tests, 10.9s
- sonnet-4-5: 3 tests, 12.0s
- opus-4-5: 3 tests, 11.2s

Closes the audit's "different model surfaces different bug" risk for the Anthropic matrix. OpenAI and Gemini remain untested live on this machine (quota / key state).

### Verified-with-bug-found: live multi-turn persistent entity

Driven against `anthropic:claude-haiku-4-5`, three sequential `Cantrip.send/2` calls on the same `Cantrip.summon/1` pid. Surfaced one bug, fixed it:

**Bug:** `EntityServer.execute_turn/4` only updated `state.messages` via `Cantrip.Turn.next_messages/3` on the *non-terminating* branch. On termination it returned the final response without folding the terminating assistant message back into `state.messages`.

**Effect:** the next `send` appended a user message to a history that still ended at the *prior* user message. After three sends the model saw `[sys, sys, user_1, user_2, user_3]` with no record of its own answers and anchored on user_1 — every prompt returned the first answer.

**Why it shipped:** the existing `Cantrip.SummonTest` multi-send case used `FakeLLM` with deterministic per-call responses that don't use context, so the test passed by construction. Real LLMs use the context, which is what surfaced this.

**Fix:** `lib/cantrip/entity_server.ex` — compute `next_messages` for both branches. Regression test in `test/summon_test.exs` asserts on the role sequence of `state.messages` directly so it catches the bug under any LLM (FakeLLM included).

Live verification after fix: three sends asking `done` with "alpha"/"beta"/"gamma" now return "alpha"/"beta"/"gamma" instead of "alpha"/"alpha"/"alpha".

## Actually broken

### Fixed: folding dropped the second leading system message

Bug:

- `Cantrip.Folding.partition/1` matched only `[%{role: :system}, %{role: :user} | rest]`.
- `Cantrip.EntityServer.initial_messages/3` emits `system, system, user` for mediums with capability text.
- On fold, the second system message entered the foldable body and could be summarized away or pushed into the recent tail depending on length.

Fix:

- `lib/cantrip/folding.ex` now preserves all leading system messages plus the first user intent.
- `test/folding_test.exs` now pins the two-system shape.

Verification:

- `mix test test/folding_test.exs` passed.

## Commands run

- `mix verify` (473 tests, 0 failures, credo clean)
- `mix test test/folding_test.exs`
- `mix test test/bash_medium_test.exs test/summon_test.exs test/composition_test.exs test/spawn_fn_test.exs`
- `mix test test/req_llm_adapter_test.exs test/runtime_boundary_spike_test.exs`
- `mix test test/mix_cantrip_familiar_test.exs`
- attempted direct `mix cantrip.cast`, blocked by sandbox `Mix.PubSub` TCP `:eperm` before task code ran
