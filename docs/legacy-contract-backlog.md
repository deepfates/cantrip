# Legacy Contract Backlog

This document is the deletion ledger for behavior discovered in the
TypeScript, Python, and Clojure implementations. The old implementations
are not active runtimes. When a row says "not pinned", it means the
behavior should either get an Elixir test/implementation or an explicit
waiver before being treated as part of the supported product.

## ACP And CLI

| Contract | Source | Elixir destination | Status |
| --- | --- | --- | --- |
| Initialize response advertises protocol version, agent identity, and session capabilities. | `py/tests/test_acp_stdio.py`, `clj/test/cantrip/acp_test.clj` | `test/acp_agent_stdio_test.exs`, `test/acp_agent_test.exs` | Partially pinned. Add serialized capability assertions. |
| Method aliases cover slash, dot, snake, camel, and legacy names. | `py/cantrip/acp_stdio.py`, `py/tests/test_acp_stdio.py` | ACP stdio adapter or explicit compatibility waiver | Not pinned. Decide whether Elixir supports aliases or rejects them. |
| Prompt text extraction accepts root `intent`, `message`, string `prompt`, typed text blocks, and content blocks. | Python/Clojure ACP routers and tests | `Cantrip.ACP.AgentHandler.extract_text/1` fixtures | Not pinned. Add fixture-driven tests or document canonical shape only. |
| Prompt response envelope handles metadata, output text, stop reasons, cancellation, max-turn, empty answer, and runtime errors. | `py/cantrip/acp_server.py`, `py/cantrip/acp_stdio.py` | `test/acp_agent_test.exs`, `test/acp_agent_stdio_test.exs` | Partially pinned for ACP-native success path. Compatibility envelope not pinned. |
| Streaming `session/update` ordering, tool ids, final message chunks, and progress summaries. | Python ACP stdio/SDK tests | `test/acp_event_bridge_test.exs`, `test/acp_handler_streaming_test.exs` | Partially pinned. Python progress/timing summaries are not pinned. |
| JSON-RPC non-request frames, parse errors, unknown methods, and pre-init errors. | Python/Clojure ACP routers | `test/acp_agent_stdio_test.exs` | Partially pinned. Add wire-level parse/non-request cases. |
| Default pipe mode, `--with-events`, legacy `--repl`/`--acp-stdio`, repo-root flags, and structured CLI errors. | `py/cantrip/cli.py`, `py/tests/test_capstone_cli_modes.py` | CLI compatibility tests or explicit deprecation note | Not pinned. Decide which invocation forms remain supported. |
| ACP probe/debug-log tooling for editor integration failures. | `py/scripts/acp_probe.py`, `py/scripts/acp_debug_log_summary.py` | `scripts/` or Mix task backlog | Not implemented. Useful release tooling, not core runtime. |

## Repo And Browser Surfaces

| Contract | Source | Elixir destination | Status |
| --- | --- | --- | --- |
| Repo paths are resolved under a configured root; empty, traversal, outside-root, symlink escape, directory, missing, and binary reads return structured observations. | `ts/src/circle/gate/builtin/repo.ts`, `py/tests/test_repo_gates.py` | `Cantrip.Gate` repo module and `test/gate_repo_test.exs` | Not pinned under repo-named gates. |
| `repo_files` returns sorted POSIX relative paths, recursive by default, excludes `.git`, `node_modules`, common binaries, symlinks, and caps results. | TypeScript/Python repo gate tests | `Cantrip.Gate.spec("repo_files")` and implementation | Not implemented as canonical gate. |
| `repo_read` supports line windows, defaults/caps, binary rejection, directory rejection, and explicit truncation markers. | TypeScript repo gate/windowing tests | `Cantrip.Gate.spec("repo_read")` | Not implemented as canonical gate. |
| Git repo gates provide log/status/diff with root-bound optional path, clean/empty messages, error observations, and truncation. | TypeScript repo gate tests | Future `Cantrip.Gate.RepoGit` | Not implemented. |
| Browser medium owns driver lifecycle, fake driver, missing-dependency errors, close-on-error, and disposed-runtime rejection. | TS browser context, Python browser tests | Future `Cantrip.Medium.Browser` | Not implemented. Browser is future work. |
| Browser tool contract is either Python action-style or TS code-eval-style, with explicit migration decision. | Python browser medium, TS browser medium | Browser design doc/tests | Not decided. |
| TS browser policies: profiles, allow/deny domains, timeout recovery, `.code`, `.reset`, output caps, opaque handle bridge. | TS browser and `js_browser` tests | Future browser backlog | Not implemented. Preserve as design reference only. |

## Providers, Usage, And Cost

| Contract | Source | Elixir destination | Status |
| --- | --- | --- | --- |
| Provider serializers handle multimodal parts, cache-control/thinking blocks, destroyed/missing tool placeholders, consecutive tool response grouping, and tool-choice mapping. | TypeScript provider serializer tests | Provider adapter regression suites | Not pinned as a unified compatibility matrix. |
| Usage accounting separates prompt, completion, cached, billable, invocation count, duration, and per-invocation breakdown. | TypeScript token/cost tests and eval harness | Future `Cantrip.Usage` / telemetry projection | Not implemented as production telemetry. |
| Cost projection is reproducible and provider-specific rather than implicit in raw usage maps. | TypeScript token/cost helpers | Future cost module or explicit non-goal waiver | Not implemented. |

## Loom, Folding, And Conformance

| Contract | Source | Elixir destination | Status |
| --- | --- | --- | --- |
| Turn shape includes id, parent, sequence, cantrip/entity ids, role, utterance, observation, terminal flags, reward, timing, and token metadata. | TS loom tests, Clojure loom tests | `Cantrip.Loom.append_turn/2`, turn structure tests | Partially pinned. Add parent/non-linear uniqueness and metadata checks. |
| Loom is append-only; reward annotation is the explicit exception. | TS/Clojure loom and conformance | `Cantrip.Loom.annotate_reward/3`, possible delete API waiver | Partially pinned. Deletion is unrepresentable rather than explicitly rejected. |
| Identity root versus synthetic call-root projection is a deliberate Elixir contract. | TS call-root thread tests, `tests.yaml` | Loom export/thread projection docs/tests | Not fully pinned. Elixir uses separate identity. |
| Thread extraction and message reconstruction return root-to-leaf paths, terminal state, assistant/tool/user observations, and unknown-leaf behavior. | TS/Python/Clojure loom extraction | `Cantrip.Loom.extract_thread/2`, future `thread_to_messages/1` | Partially pinned. Public message projection is missing. |
| Tree helpers expose roots, children, leaves, and fork point, or are explicitly non-public. | TS loom tree tests | `Cantrip.Loom` helper backlog | Not pinned as public API. |
| Fork/replay hydrates gate observations without re-executing stateful gates. | TS/Python conformance, `tests.yaml` LOOM cases | `Cantrip.fork/4`, conformance expectations | Partially pinned. Add strict stateful no-reexecution test. |
| Folding is a view, preserves identity and recent turns, marks folded spans, and has clear trigger semantics. | TS folding tests, `tests.yaml` | `Cantrip.Folding`, conformance docs | Partially pinned. Trigger semantics need a canonical Elixir decision. |
| Loom export redacts by default and conformance actually checks exported text. | Clojure conformance/redaction | Future `Cantrip.Loom.export_jsonl/2`, `Cantrip.Redact` | Not pinned. Current conformance export checks are weak/no-op. |
| Conformance expectations fail loudly instead of silently skipping P0 checks. | Clojure conformance runner | `test/support/conformance/*` | Partially pinned. Add unsupported-key accounting and stricter fork/export checks. |
| Durable storage append failures are visible. | Elixir storage review plus legacy persistence lessons | `Cantrip.Loom.Storage` callbacks | Not pinned. Explicit backend init is loud; append failure policy needs a decision. |

## Code Medium And Ward Policy

| Contract | Source | Elixir destination | Status |
| --- | --- | --- | --- |
| Required code tool, explicit `done`, persistent safe bindings, gate projection, stdio capture, and recoverable eval errors. | Clojure medium, TS JS/VM, Python executor | `Cantrip.Medium.Code`, `Cantrip.CodeMedium`, Dune tests | Pinned in Elixir. |
| Child delegation helpers are injected only when authorized and failures are visible to the parent. | Clojure runtime/medium, Python executor, TS call gates | `Cantrip.CodeMedium`, `Cantrip.cast/3`, `Cantrip.cast_batch/2` | Partially pinned. Budget mapping still needs tests. |
| Child budgets cover depth, batch size, concurrency, and per-turn child call count or an explicit replacement. | Clojure ward docs/runtime | `Cantrip.WardPolicy` and composition tests | Not fully pinned. `max_child_calls_per_turn` has no established equivalent. |
| Default unrestricted Elixir evaluation versus sandbox-by-default is a documented product decision. | Clojure SCI default, Python/TS sandbox warnings | `DEPLOYMENT.md`, capability text | Needs explicit safety note. Dune covers hardened path; default is intentionally not a sandbox. |
| Dangerous operations are blocked in hardened mode; capability text matches actual evaluator. | Clojure preflight, Dune tests | `Cantrip.CodeMedium.DuneSandbox`, prompt/docs | Mostly pinned for Dune. Audit public prompts/docs. |
| Source/form complexity wards such as `max_forms` are ported or retired. | Clojure `max-forms` policy | `Cantrip.WardPolicy` backlog | Not pinned. Timeout/reductions are present, form count is not. |
| Minecraft medium fate is explicit. | Clojure medium/tests | Deprecation note or Elixir port | Not implemented. Treat as retired unless product direction changes. |

## RLM, Familiar, And Council

| Contract | Source | Elixir destination | Status |
| --- | --- | --- | --- |
| Large context lives in the code medium as data, not in the prompt; model explores with code and returns compact synthesis. | TS RLM examples/evals | Elixir RLM eval harness and Familiar docs | Not pinned by evals. Pattern is documented but not benchmarked. |
| Eval harness compares sandbox, entity full-output, entity metadata-only, and in-context baselines with usage metrics. | `ts/tests/evals/*` | Future `test/evals/*` opt-in suite | Not implemented. |
| Recursive child delegation enforces depth, strips/fails delegation at max depth, supplies parent context, and keeps parent alive on child errors. | TS recursive/call gates, Clojure runtime | Familiar behavior tests and `Cantrip.new_child` path | Partially pinned. Add max-depth stripping and context fallback tests. |
| Batch/council fanout validates inputs, bounds concurrency, preserves result order, handles partial failures, and grafts child turns. | TS `call_entity_batch`, `cast_batch` | `Cantrip.cast_batch/2`, Familiar tests | Partially pinned. Add concurrency, partial-failure, and grafting checks. |
| Elixir intentionally replaces TS `cantrip/cast/dispose` host functions with public `Cantrip.new/cast/cast_batch`. | TS cantrip functions, Elixir Familiar tests | `Cantrip.Familiar` prompt/tests | Pinned as a vocabulary decision. |
| Child construction inheritance covers LLM selection, requested gates, root deps, wards, retry, folding, and depth stripping. | Clojure runtime, Elixir child path | `Cantrip.parent_context/2`, child construction tests | Not fully pinned. Add explicit matrix tests. |
| Familiar root observes/navigates but delegates file reads/action/semantic work to children with inherited root. | TS Familiar example, Elixir Familiar tests | `Cantrip.Familiar.new/1`, real-LLM integration tests | Partially pinned. Keep deterministic and real-LLM coverage. |
| Familiar memory survives sends and summons with Mnesia/JSONL storage and exposes `loom.turns`. | TS/Python Familiar examples, Elixir tests | Familiar storage tests, launcher tests | Pinned by current Elixir tests; rerun after deletion. |
| Non-binary `done` values survive API cast and ACP translation. | Elixir-strengthened behavior | `Cantrip.Gate`, `Cantrip.ACP.EventBridge` | Pinned in Elixir; keep as production contract. |

## Deletion Rule

Deleting the old implementation code is acceptable only as a repo-hygiene
move, not as a claim of full behavioral parity. This document and
`docs/legacy-implementation-harvest.md` preserve the actionable
contracts. A row remaining "not pinned" is not by itself a reason to keep
stale runtime code in the active tree; it is a reason to keep a visible
implementation task, test task, or explicit waiver until the Elixir
package settles that behavior.
