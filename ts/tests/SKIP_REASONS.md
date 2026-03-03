# Skip Reasons (Cantrip v0.2.0 TS Cutover)

This file documents intentional skip categories observed in the current `bun test` run (91 skips).

## 1) Canonical conformance scenarios
- Why skipped: The canonical conformance set marks some cases as skipped, and `tests/conformance.test.ts` also skips configured rule prefixes.
- Scope: `tests/conformance.test.ts` entries shown as:
  - `marked skip in yaml`
  - `rule prefix COMP-*`
  - `rule prefix PROD-*`
  - `code_circle type` cases
- Status: Intentional; controlled by canonical scenario metadata and explicit skip-prefix logic.

## 2) OpenRouter integration (credential-gated)
- Why skipped: `tests/integration/integration_openrouter.test.ts` uses `test.skip` unless `OPENROUTER_API_KEY` is present.
- Scope: 2 tests (`returns a response`, `returns tool calls when required`).
- Status: Intentional; requires an OpenRouter key.

## 3) LM Studio integration (local-service gated)
- Why skipped: `tests/integration/integration_lmstudio.test.ts` uses `test.skip` unless `LM_STUDIO_TEST` is enabled.
- Scope: 2 tests (`returns a response`, `returns tool calls when required`).
- Status: Intentional; requires a running local LM Studio server and opt-in.

## 4) Benchmark/eval suites (real LLM + long-running)
- Why skipped: Eval benchmarks are intentionally skipped by default due runtime/cost/non-determinism.
- Scope:
  - `tests/evals/bench_multihop.test.ts`
  - `tests/evals/bench_aggregation.test.ts`
  - `tests/evals/bench_oolong.test.ts`
  - `tests/evals/bench_niah.test.ts`
- Status: Intentional default behavior.

## 5) Example quick-start live gate
- Why skipped: `tests/examples.test.ts` skips `02_quick_start runs` unless both:
  - `RUN_LIVE_LLM_TESTS=1`
  - `ANTHROPIC_API_KEY` is available
- Status: Intentional opt-in for a live-provider example.
