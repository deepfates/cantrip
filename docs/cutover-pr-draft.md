# Solid V1 Runtime Cutover PR Draft

## Summary

This cutover turns the Elixir Familiar runtime into a clearer BEAM-native spine
without changing the project into a generic agent framework.

The main shift is that `EntityServer` now owns process identity, lifecycle,
stream emission, recursion, and state transition, while named runtime
boundaries own the cognitive and operational pieces:

- `Cantrip.Turn` owns request preparation, response classification,
  continuation messages, termination decisions, final response shaping, and turn
  attributes.
- `Cantrip.ProviderCall` owns provider invocation, retry, timing, and streamed
  callback plumbing.
- `Cantrip.Medium.*` owns medium presentation and execution adapters for
  conversation, code, and bash.
- `Cantrip.Gate.Executor` owns ordered conversation gate execution.
- `Cantrip.WardPolicy` owns ward queries and composition.
- `Cantrip.Event` owns event envelopes and mechanically ordered per-turn runtime
  events.
- `Cantrip.Loom` now supports generic event append while preserving turn-shaped
  compatibility APIs.

Solid V1 stays focused on the runtime that exists today: Familiar on the BEAM,
ordered events, loom compatibility, medium/ward boundaries, ACP/CLI stability,
safe diagnostics, and fast green tests.

## Runtime/Protocol Fixes

- Streamed LLM deltas now use the runtime event callback path instead of a
  separate relay process, so event order is mechanically closer to execution
  order.
- ACP final answers are single-sent: direct fallback is used only for
  genuinely non-streaming sessions or dead bridge cases. Streaming sessions set
  `streaming?: true`, so `:no_answer` and `:timeout` never direct-send an
  answer that the bridge may still deliver.
- ACP bridge lifetime is tied to the pid-backed connection, explicit owner, or
  caller for custom/test bridges.
- Provider retries are disabled for streaming requests so partial output cannot
  be replayed after subscribers may already have seen it.
- Diagnostics are opt-in for ACP, use a per-process random distributed Erlang
  cookie, redact secret-shaped data by default, and redact cached last answers
  in both returned and printed dumps.
- Repo-wide formatting is clean.

## Tests

- Full suite: `411 tests, 0 failures`.
- Formatter: `mix format --check-formatted` passes.
- Compile hygiene: `mix compile --warnings-as-errors` passes.
- Diff whitespace: `git diff --check` passes.
- Credo: no warnings, readability, or software-design findings remain; only
  non-blocking refactor suggestions are reported.

## Deliberately Deferred

This PR does not implement V1.5/V2 evolution features:

- no artifact store
- no candidate transaction
- no lineage/evaluation projections
- no LiveView workbench
- no autonomous self-modification path

The loom now has the generic event-log compatibility needed for those later
features, but the concrete evolution vocabulary stays in planning docs rather
than becoming Solid V1 runtime API.
