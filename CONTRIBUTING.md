# Contributing

Cantrip is now an Elixir package first. The implementation and ExUnit suite
are the authoritative contract.

## Workflow

1. Write focused ExUnit coverage before changing behavior.
2. Keep changes scoped to the runtime surface being changed.
3. Prefer BEAM-native ownership: supervised processes, behaviours at real
   boundaries, explicit state where possible.
4. Treat expected operational failures as observations. Let unexpected bugs
   crash under supervision.
5. Keep durable docs current when public API, deployment posture, or package
   shape changes.

## Runtime Principles

- The circle is the safety boundary.
- The medium determines the shape of thought.
- Errors are observations.
- Folding is a view over prompt context. It must never delete the underlying
  loom record, and it must preserve all leading `:system` messages and the
  original user intent in the prompt context the model sees — otherwise the
  entity loses its identity or medium physics partway through a session.
- The loom is append-only; reward annotation is the exception.
- Code medium evaluates LLM-emitted Elixir inside a child BEAM via Dune by
  default (`sandbox: :port`); `:unrestricted` and `:port_unrestricted` are
  explicit escape hatches.
- Safety is layered: gate root validation, redaction, the port/Dune boundary,
  and deployment isolation.

## Quality Gates

Run before opening or updating a PR:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --ignore refactor
```

`mix verify` runs the same gate. Run `./scripts/check_signer_policy.sh` when
changing `compile_and_load` policy, signer configuration, or hot-load wards
— see [docs/signer-key-runbook.md](./docs/signer-key-runbook.md) for what
that policy is for and how to rotate keys.

### Live integration tests

`mix verify` is unit-test scope. Live tests against real providers exist
under `test/real_llm_*`, `test/familiar_real_llm_*`, `test/live_anthropic_test.exs`,
and `test/zed_trace_replay_test.exs`. They are gated by `Cantrip.Test.RealLLMEnv`
(set `RUN_REAL_LLM_TESTS=1` plus `CANTRIP_LLM_PROVIDER` / `CANTRIP_MODEL` /
provider-specific API key) and skip cleanly otherwise.

Run before tagging a release, and any time a change touches the LLM adapter,
medium dispatch, loom, folding, multi-send behavior, or anything else with a
contract between the runtime and a real provider:

```bash
RUN_REAL_LLM_TESTS=1 CANTRIP_LLM_PROVIDER=anthropic ANTHROPIC_MODEL=claude-haiku-4-5 \
  CANTRIP_TIMEOUT_MS=120000 \
  mix test test/live_anthropic_test.exs test/real_llm_integration_test.exs
```

The class of bugs these catch is "code paths that look fine because the unit
mocks return what the production code expects, not what real providers
actually return." Several were found this way during v1 prep; see
`docs/v1-audit.md`.

CI runs the Anthropic live subset on pushes to `main`, `release/**`, and
`v*` tags. Those refs require the `ANTHROPIC_API_KEY` repository secret; PRs
run `mix verify` only so routine review does not spend provider tokens.
