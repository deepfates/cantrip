# Post-v1 Cleanup Status

Living tracker for the post-v1 hardening/cleanup pass. Updated by codex
and claude on every substantive commit so anyone — codex, claude, the
board (user) — can see at-a-glance state without reading scratch.

**Working standard:** "Solve, not administratively close." An issue leaves
the open set only when the underlying concern is gone and the repo contains
evidence (passing regression test pinning the desired behavior, or a doc/
contract change).

**Sources:** the open GitHub issue tracker, the local
`comprehensive_elixir_codebase_cleanup_guide.md` operational reference
(currently untracked), and the v1.0.0 release commit `9638ea2` as the
baseline.

---

## Per-Issue Status

| # | Title | Status | Evidence / Next Step |
|---:|---|---|---|
| 3 | Familiar's cantrip/cast/dispose isomorphic with host Cantrip API | **partial** | Code-medium proxies `Cantrip.new/cast/cast_batch` via port-child bindings (codex verified, `lib/cantrip/medium/code/*`). **Open question:** Dune sandbox intentionally does not mirror — needs board decision (Phase 5). |
| 8 | Eval harness for Familiar prompts | **deferred-pending** | Post-v1 feature scope. Board decision pending on `feature` label vs in-scope (Phase 8). |
| 9 | First-class `mix` gate | **deferred-pending** | Post-v1 feature scope. Same as #8. |
| 10 | Distributed Familiar | **deferred-pending** | Post-v1 feature scope. Same as #8. |
| 11 | Full telemetry coverage + observability runbook | **deferred-pending** | Post-v1 design scope (Pass 13). Same as #8. |
| 12 | Dune sandbox over-restricts | **deferred-pending** | Tied to #3 Dune-parity board decision (Phase 5). |
| 20 | Sandbox roots for filesystem gates | **ready-to-close** | Pre-v1 issue cites a `read` gate that no longer exists. `read_file`/`list_dir`/`search` route through `Cantrip.Gate.Path.validate/2`. Evidence: `test/gate_validation_test.exs:49+` (missing root, all three gates), `:78+` (path traversal, all three). Commit `d12875c`. |
| 21 | Avoid unbounded atom creation from external strings | **ready-to-close** | `d12875c` removed unbounded atom creation at parent-context + gate-binding sites. `bc2bf01` tightened JSONL restore, Familiar table/node atoms, and cookie atoms. Follow-up removed broad `allow_compile_namespaces`; `compile_and_load` now requires exact `allow_compile_modules`, so module atoms come only from caller-provided bounded vocabularies. |
| 22 | Reject unknown medium types | **ready-to-close** | Validation added in `lib/cantrip/circle.ex` via `validate_known_medium/1`; `80287b7` restored `normalize_type/1` to a bounded codomain (`:conversation | :code | :bash | :unknown`). Evidence: `test/divergence_fixes_test.exs`. |
| 23 | call_entity_batch parallel contract | **ready-to-close** | `Cantrip.cast_batch/2` uses `Task.async_stream/3` with `ordered: true`. Evidence: `test/composition_test.exs` pins request order, child-turn grafting, and a two-child concurrency probe where both heterogeneous children must enter `query/2` before either is released. |
| 24 | Move long-running entity runs out of blocking GenServer calls | **live, design-phase** | Codex pass-2 confirmed `EntityServer.run/1` etc. still inside `GenServer.call(..., :infinity)`. Provider/medium work blocks the mailbox. Phase 6. |
| 25 | Multi-system messages Anthropic/Gemini | **ready-to-close** | Evidence: `test/req_llm_adapter_test.exs` fixtures a multi-system-message `ReqLLM.Context` and asserts Anthropic preserves both system blocks while Gemini preserves both in `systemInstruction`. |
| 26 | Refresh README examples | **closed-with-proof** | Specific examples in issue body are no longer stale (verified). Drift now CI-detectable via `test/readme_examples_test.exs` (5 tests, green). Commit `05363e6`. Pending: close on GitHub with comment. |
| 27 | Replace code-medium bare function rewriting with parser-aware handling | **ready-to-close** | `Cantrip.Medium.Code.add_dot_calls/2` now parses with `Code.string_to_quoted/1` and rewrites local gate-call AST nodes instead of regexing source text. Evidence: `test/code_medium_ergonomics_test.exs` covers strings, remote calls, already-dotted calls, custom gates, and definition heads. |
| 30 | Surface malformed-JSON tool-call arguments | **ready-to-close** | Decode failure preserved as `args_raw` + `args_decode_error` on tool_call; executor emits structured error observation without invoking target gate. Evidence: `test/req_llm_adapter_test.exs` executor regression. Commit `d12875c`; blocker seam fixed in `80287b7` by making `normalize_response/1` private again. |
| 31 | Mnesia loom storage swallows create_schema errors | **ready-to-close** | `ensure_schema/0` now propagates non-`already_exists` errors. Evidence: `test/loom_storage_test.exs`; `test/loom_mnesia_storage_test.exs` now reads through the public storage behaviour. Commit `d12875c`; public `read_events/2` seam privatized in `80287b7`. |

**Status legend:**
- `ready-to-close` — underlying concern solved, evidence in tree, ready to close on GitHub with proof
- `ready-to-close-with-evidence-needed` — solved by current code per source trace; needs explicit regression test before close
- `ready-to-close-after-blocker-fix` — solved, but cold-review surfaced a blocker that must land first
- `closed-with-proof` — closed (or about to be) on GitHub
- `partial` — partial solve; remaining work tracked
- `live, design-phase` — substantive defect, needs design before implementation
- `live` — defect, implementation lane open
- `deferred-pending` — feature scope, awaiting board decision on label/scope

---

## Per-Cleanup-Pass Status

| Pass | Topic | Status | Notes |
|---:|---|---|---|
| 0 | Baseline & inventory | **done** | v1.0.0 shipped with `mix verify` clean. This doc + the open issue tracker IS the inventory. |
| 1 | Transformation safety | **ready-to-close-for-tracked-issues** | #27 replaced the code-medium regex source rewriter with parser-aware AST rewriting. No other regex-based source transforms found. |
| 2 | Boundary / DTO integrity | **ready-to-close-for-tracked-issues** | #22 and #30 are ready-to-close after `d12875c` + `80287b7`; #25 now has provider-encoding evidence in `test/req_llm_adapter_test.exs`. |
| 3 | Atom safety | **ready-to-close-for-tracked-issues** | `d12875c` covers parent-context + gate-binding; `bc2bf01` covers JSONL replay, Familiar operational atoms, and persisted cookie shape. Follow-up makes `compile_and_load` exact-module allowlist only. |
| 4 | Configuration / ambient authority | **scan-needed** | No open issue. Need to scan `Application.get_env`/`System.get_env` usage in non-boot paths. Likely scan-clean given Cantrip's explicit-injection idiom. |
| 5 | Secret redaction & error sanitization | **done-for-current-findings** | `075878a` added `Cantrip.SafeFormat` and wired redaction into adapter errors, JSONL inspect fallbacks, and port code-medium error surfaces. Evidence: `test/redact_test.exs`; `mix verify` green. |
| 6 | Unsafe deserialization / runtime eval | **scan-needed** | `compile_and_load` is the relevant gate; touched by #21 partial. `Code.eval_*` usage to be scanned. |
| 7 | OTP lifecycle / supervision | **partial** | #24 is the main live issue. Bare `spawn`/`Task.start` to be scanned. |
| 8 | Mailbox / backpressure | **scan-needed** | Adjacent to #24. `GenServer.cast` usage to be scanned. |
| 9 | GenServer functional-core cleanup | **partial** | #24 + #23 both partially in scope. |
| 10 | Serialization / protocol / versioning | **scan-needed** | Loom JSONL format is unversioned. Worth verifying whether v1 declared an implicit "loom format v1" or if this is a real gap. |
| 11 | Persistence / state backend cleanup | **partial** | #31 + Mnesia restart persistence verified working. Loom storage backends exist (jsonl, mnesia, memory). |
| 12 | Package / dependency boundaries | **partial** | #3 maps here (Familiar/host API isomorphism). |
| 13 | Observability / context propagation | **deferred** | #11 covers this entirely. |
| 14 | Idiomatic / performance | **not-started** | Late pass per guide. |
| 15 | Final verification / governance lock-in | **not-started** | Final pass per guide. CI gates from cleanup guide line 1463+ to be added. |

**Status legend:** `done`, `in-progress`, `partial`, `scan-needed`, `deferred`, `not-started`.

---

## Phase Plan

The 8-phase critical path from current state to 0 issues + clean codebase
(per Claude's course-correction `scratch/agent-comms/inbox/20260528T010844Z`).

| Phase | Scope | Status |
|---:|---|---|
| 1 | Wrap `d12875c` properly: fix 4 cold-review blockers, close #20/#22/#26/#30/#31 with proof | **blockers-fixed** (`80287b7`); GitHub close-with-proof comments still pending |
| 2 | Wrap pre-v1 verified-stale items: add regression tests + close #23 and #25 | **evidence-added**; GitHub close-with-proof comments still pending |
| 3 | Pass 5 secret redaction coverage | **complete for current findings** (`075878a`) |
| 4 | #21 remaining atom-creation sites | **evidence-added**; GitHub close-with-proof comment pending |
| 5 | #3 Dune-parity decision (board question) | **pending — needs board input** |
| 6 | #24 OTP lifecycle design + implementation | **pending** |
| 7 | #27 parser-aware code-medium | **evidence-added**; GitHub close-with-proof comment pending |
| 8 | Feature issues (#8, #9, #10, #11, #12) — keep or label-and-defer | **pending — needs board input** |

---

## Board questions queued (surface to user when their phase arrives)

1. **#3 Dune parity** — implement parity, or document Dune as deliberately-restricted-medium variant? (Phase 5)
2. **Feature issues (#8, #9, #10, #11, #12)** — pull into scope, label `feature` and defer, or close with "out of cleanup scope"? (Phase 8)
3. **`comprehensive_elixir_codebase_cleanup_guide.md`** — currently untracked at repo root. Long-term home: `docs/`, `scratch/` (gitignored), or delete-after-cleanup-complete?

---

## Working agreements

- Every substantive commit gets a cold-reviewer-agent pass (claude lane).
- Every "close" cites a regression test or doc change in the comment.
- One cleanup-guide pass per commit going forward (`d12875c` bundled, accepted as exception).
- `mix verify` green before commit, always.
- This file updates on commit (whoever ships, updates).
