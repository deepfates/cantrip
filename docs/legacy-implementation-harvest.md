# Legacy Implementation Harvest

The TypeScript, Python, and Clojure implementations were scaffolding for
learning the Cantrip pattern from multiple angles. They are no longer
active runtime targets. This document preserves the useful lessons to
carry into the canonical Elixir implementation; the old code remains
available through git history.

## TypeScript

Keep as design/backlog material:

- **Browser and `jsBrowser` medium.** The Taiko-backed browser context and
  handle-table pattern are the strongest unique runtime idea. If Elixir
  grows a browser medium, preserve opaque host-side handles rather than
  serializing browser objects through the model context.
- **Repo/file gates.** Port the shape of `repo_files`, `repo_read`,
  git-status/diff/log observations, root confinement, binary exclusion,
  line windows, result caps, and explicit truncation markers.
- **Provider serializer edge cases.** Mine OpenAI, Anthropic, and Gemini
  serializer tests for multimodal parts, cache-control/thinking blocks,
  grouped tool responses, and tool-choice mapping.
- **Token and cost accounting.** Preserve cached-token separation,
  per-invocation usage history, and cost projections as a future
  observability slice.
- **Eval harness ideas.** Keep the RLM benchmark shape: large context
  lives in the medium, model explores by code, summaries return upward.
- **Examples 15, 16, 20, 21.** Useful as teaching references for browser
  research, Familiar orchestration, data exploration, and `A = M union G
  - W`.

Concrete artifacts harvested:

| Legacy path | What to preserve | Elixir destination |
| --- | --- | --- |
| `ts/examples/20_data_exploration.ts` | RLM pattern: data lives in medium state, model explores by code, parent sees compact metadata. | Future `Cantrip.RLMDataExplorationTest`; docs for code-medium RLM. |
| `ts/examples/16_familiar.ts` | Familiar coordinator recipe: repo observation, child construction, `cast_batch`, persistent loom. | `Cantrip.Familiar` prompt/docs; `Cantrip.FamiliarBehaviorTest`. |
| `ts/src/circle/gate/builtin/cantrip.ts` and `ts/tests/unit/circle/cantrip_functions.test.ts` | Linear child handles, `cantrip`/`cast`/`cast_batch`/`dispose`, default child wards, batch caps, error cases. | Backlog `Cantrip.CantripConstructionGatesTest`; decision on handle lifecycle. |
| `ts/src/circle/gate/builtin/call_entity_gate.ts` and `ts/tests/unit/cantrip/call_entity_gate.test.ts` | Depth pruning, parent context fallback, child errors as values, batch chunking, progress events. | `Cantrip.SpawnFnTest`, composition tests, future `Council` semantics. |
| `ts/tests/spec/spec_composition.test.ts` | Delegation behavior matrix: child independence, batch order, depth, cancellation, failure observation, loom linkage. | Reconcile with `test/m5_*` and `test/m18_*`; add gaps or waivers. |
| `ts/src/loom/*` and `ts/tests/unit/loom/*` | Thread extraction, forked trees, reward annotation, fold records, root-to-leaf message views. | `Cantrip.Loom`, `Cantrip.Folding`, future `Cantrip.Loom.ThreadView`. |
| `ts/src/circle/medium/js_browser.ts` and `ts/tests/unit/js_browser.test.ts` | Opaque host-side browser handles with sandbox-side wrappers and cross-turn handle survival. | Future `Cantrip.Medium.Browser.HandleTable` and `Cantrip.BrowserMediumHandleTest`. |
| `ts/src/circle/medium/browser/context.ts` and `ts/tests/unit/browser.test.ts` | Browser profiles, domain policy, session reset, code export, timeout recovery. | Future browser medium backlog, not current runtime. |
| `ts/src/circle/gate/builtin/repo.ts` and `ts/tests/unit/circle/repo_gates.test.ts` | `repo_files`, `repo_read`, git log/status/diff, root confinement, binary rejection, line windows, caps. | Future `Cantrip.Gates.Repo` and `Cantrip.RepoGatesTest`. |
| `ts/src/llm/*/serializer.ts` and `ts/tests/unit/llm/serializer_*.test.ts` | OpenAI destroyed-tool placeholders, Anthropic cache-control placement, Gemini consecutive tool grouping. | Provider adapter regression tests. |
| `ts/src/llm/tokens/*` and token/cost tests | Usage history, cached-token accounting, cost projection. | Future `Cantrip.Usage` / `Cantrip.Cost` telemetry projection. |
| `ts/tests/evals/harness.ts` and `ts/tests/evals/bench_*.test.ts` | Optional RLM eval baselines: JS sandbox, entity full-output, entity metadata-only, in-context. | Future non-CI `test/evals/*` harness. |

Do not port now:

- QuickJS or `node:vm` as runtime surfaces.
- TypeScript ACP server internals.
- Zod schema inference.
- JSONL-only loom assumptions.
- TypeScript dependency-injection machinery.

## Python

Keep as design/backlog material:

- **ACP compatibility cases.** Port missing slash/dot method aliases,
  cancellation, session lifecycle, prompt shape, parse-error, fallback
  answer, and max-turn stop-reason tests into ExUnit where relevant.
- **SQLite loom projection.** Elixir's source of truth should stay BEAM
  native, but a SQLite export/projection could help external dashboards
  and audit tooling.
- **Large-file clipping.** Add `read_file` byte/line limits with explicit
  truncation observations for production Familiar deployments.
- **Browser driver interface.** If browser work resumes, use the simple
  in-memory/Playwright driver split as a sketch.
- **Readable API narrative.** Preserve the "LLM + Identity + Circle" path
  in docs even though the Elixir runtime has more production machinery.

Concrete artifacts harvested:

| Legacy path | What to preserve | Elixir destination |
| --- | --- | --- |
| `py/cantrip/acp_stdio.py` and `py/tests/test_acp_stdio.py` | Slash/dot JSON-RPC aliases, snake/camel session IDs, prompt block variants, non-request frame ignore, parse errors, notification ordering. | `Cantrip.ACP.WireAliasCompatTest`; ACP fixture backlog. |
| `py/cantrip/acp_server.py` and `py/tests/test_acp_server.py` | Session transcript continuity, event scoping, fallback text, cancelled stop reason, max-turn stop reason, no-progress behavior. | `Cantrip.ACP.SessionSemanticsTest`, `Cantrip.ACP.NonTerminalResponseTest`, `Cantrip.NoProgressGuardTest`. |
| `py/scripts/acp_probe.py` and `py/scripts/acp_debug_log_summary.py` | Deterministic stdio probe and debug-log summarizer for editor failures. | Future `scripts/acp_probe.exs` or shell probe; deployment docs. |
| `py/cantrip/cli.py` and CLI tests | Pipe/REPL/ACP modes, JSONL structured errors, `--with-events`, repo-root resolution, help/config precedence. | `Cantrip.CLI.UXParityTest` and Mix task tests. |
| `py/cantrip/runtime.py` repo gate branches and `py/tests/test_repo_gates.py` | Root-confined repo listing/read, path escape rejection, byte cap, truncation marker. | Future repo-context gates; combine with richer TS repo gate shape. |
| `py/cantrip/runtime.py` cancellation/no-progress branches and ACP tests | Cancellation polling, unavailable-gate fast stop, stagnant code-loop guard. | Runtime policy decision; `Cantrip.NoProgressGuardTest`. |
| `py/cantrip/loom.py` `SQLiteLoomStore` | SQLite `threads`/`turns` projection shape with JSON columns and WAL mode. | Optional SQLite projection/export, not canonical storage. |
| `py/cantrip/browser.py`, `py/cantrip/mediums.py`, browser tests | Memory/Playwright driver split and cleanup-on-error behavior. | Browser medium design sketch. |
| `py/docs/CAPSTONE_INTERACTIVE.md` | Operator docs for env, pipe, REPL, ACP stdio, probes, Zed/Toad debugging. | `DEPLOYMENT.md` and ACP ops backlog. |
| `py/examples/patterns/07_full_agent.py`, `08_folding.py`, `10_loom.py` | Clear examples for error steering, folding without loom loss, terminated vs truncated audit trail. | Elixir README/PATTERNS teaching language. |

Do not port now:

- In-process Python `exec()` sandbox.
- Python runtime/domain model.
- HTTP router implementation.
- OpenAI-compatible provider code.
- Runnable examples as maintained artifacts.

## Clojure

Keep as design/backlog material:

- **Direct `tests.yaml` runner lessons.** Compare any skipped or specially
  normalized conformance cases against the Elixir runner before declaring
  the YAML suite fully canonical.
- **Ward and threat policy docs.** Fold concise risk/control tables into
  Elixir deployment documentation.
- **Sandbox preflight.** Consider AST/form complexity checks and clearer
  structured observations before expensive or unsafe code evaluation.
- **Child-call limits.** Evaluate a `max_child_calls_per_turn` ward
  distinct from batch size and concurrency limits.
- **Redaction policy.** Keep redaction before entity context and before
  protocol/debug export, not just in UI rendering.

Concrete artifacts harvested:

| Legacy path | What to preserve | Elixir destination |
| --- | --- | --- |
| `clj/src/cantrip/conformance.clj` | Direct `tests.yaml` runner with expectation/unsupported accounting, ACP pseudo-invocations, fork/thread checks, redaction exclusions. | Compare with `Cantrip.Conformance.Runner` and `Cantrip.Conformance.Expect`; add missing keys or waivers. |
| `clj/scripts/conformance_preflight.rb` | Cheap preflight counts for rule families, skipped cases, total cases. | Future `mix cantrip.conformance --preflight` or conformance report. |
| `clj/docs/THREAT_MODEL.md` | Operational risks: unbounded composition, arbitrary code, host overexposure, traversal, implicit world bindings. | `DEPLOYMENT.md` runtime threat model. |
| `clj/docs/WARD_POLICY.md` | Recommended ward defaults and controls: `max-child-calls-per-turn`, `allow-require`, `max-eval-ms`, `max-forms`. | `Cantrip.WardPolicy` docs/backlog; deployment recommended defaults. |
| `clj/src/cantrip/medium.clj` and `clj/test/cantrip/medium_test.clj` | SCI preflight: forbidden forms, require blocking, form count, timeout, host binding whitelist. | Future `Cantrip.CodeMedium.Policy`; Dune/code-medium policy tests. |
| `clj/src/cantrip/runtime.clj` and `clj/test/cantrip/runtime_test.clj` | Strict child request validation, child-call budget, child turn cap, retries, folding marker placement, ephemeral refs. | Composition/folding/runtime tests; child-call ward decision. |
| `clj/src/cantrip/redaction.clj` and redaction tests | Recursive redaction policy and placement before export/protocol/model exposure. | `Cantrip.RedactTest`; deployment docs. |
| `clj/src/cantrip/loom.clj` and loom tests | Append-only loom, reward annotation exception, root-to-leaf thread extraction, default redacted export. | Loom tests and future export docs. |
| `clj/src/cantrip/protocol/acp.clj` and ACP tests | Prompt shape extraction, persistent session entity, debug events, redacted ACP output. | ACP tests where not already covered. |
| `clj/src/cantrip/examples.clj`, `clj/test/cantrip/examples_test.clj`, `clj/EXAMPLES.md` | Structural example tests: scripted mode, no silent fallback, pattern coverage, child identity not inherited, done schema. | `CantripExamplesTest`; `docs/patterns.md`. |

Do not port now:

- SCI runtime code.
- Minecraft medium.
- Clojure OpenAI provider.
- Hand-rolled dotenv.
- Clojure ACP router.

## Elixir Backlog From The Harvest

1. Add repo-context gates: inventory, line-windowed reads, git status,
   git diff, git log, binary detection, result caps, and citations.
2. Add large-observation handling: clipping, artifact references, and
   explicit truncation markers.
3. Add child-call budget wards, including per-turn child call count and
   cumulative recursive budget accounting.
4. Add a first-class `Council` or `ReviewRound` layer: roles, isolated
   reviewer scratch, structured verdicts, adjudication, dissent, and
   durable decision events.
5. Add loom retrieval/indexing by entity, file, gate, error, lineage,
   task, and time.
6. Add a SPEC MUST coverage report that maps rules to ExUnit modules or
   explicit waivers.
7. Port missing ACP compatibility tests from the Python implementation.
8. Reconcile the unrestricted Elixir code medium, Dune opt-in, and
   deployment isolation into one safety contract.
9. Add optional SQLite export/projection only if non-BEAM analysis tools
   need it.
10. Build an optional real-LLM eval harness for Familiar and council
    behavior; keep it out of default CI.
11. Add ACP wire alias/session compatibility tests or explicit waivers:
    slash/dot methods, prompt shapes, session lifecycle, cancellation,
    non-request frames, fallback text, and max-turn stop reasons.
12. Add CLI UX parity tests for pipe/REPL/ACP modes, JSONL errors,
    event output, repo-root resolution, and help/config precedence.
13. Decide no-progress behavior: stagnant code loops and unavailable
    gates should either stop with structured observations or be left to
    max-turn wards with a documented rationale.
14. Decide code-medium preflight policy: AST/source complexity,
    forbidden forms/modules, host binding whitelist, and Dune parity.
15. Decide child handle semantics: opaque/linear/disposable handles
    versus direct reusable `Cantrip` structs and process IDs.

## Archive Policy

The active tree should contain the Elixir implementation and distilled
lessons, not several stale runtime branches. For old implementation code,
use git history. For planned work, use this document or issues.
