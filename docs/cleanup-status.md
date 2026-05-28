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

## Headline

**13 of 16 starting issues closed with proof. 4 new issues filed: #32 Pass 10
versioning, #34 Pass 5 follow-up, #35 compile_and_load policy gaps, #36
cookie overwrite. #11, #32, #34, #35, and #36 are closed with proof. 3
feature-roadmap issues labeled `feature` and kept open. No active cleanup
issues remain.**

The post-d12875c cold review caught two reward-hacking patterns: Pass 5 was
marked "done" while ~30 boundary inspect/Exception.message bypass channels
remained (#34); the #21 closure claimed module-redefinition safety beyond
what was actually implemented (#35). The atom-safety claim from #21 still
holds — those are adjacent concerns, not a reopen.

---

## Per-Issue Status

| # | Title | Status | Evidence / Next Step |
|---:|---|---|---|
| 3 | Familiar isomorphic with host Cantrip API | **closed** | Port sandbox does proxy; Dune is deliberate restricted variant. Documented in `docs/port-isolated-runtime.md`. |
| 8 | Eval harness for Familiar prompts | **open, `feature`** | Roadmap, not cleanup defect. |
| 9 | First-class `mix` gate | **open, `feature`** | Roadmap, not cleanup defect. |
| 10 | Distributed Familiar | **open, `feature`** | Roadmap, not cleanup defect. |
| 11 | Telemetry coverage + observability runbook | **closed** | `Cantrip.Telemetry.events/0` is the runtime registry. Events now carry `trace_id`; root casts accept external trace IDs and child casts inherit them. Runtime emits entity/turn/gate/code/bash lifecycle events plus usage, redaction-hit, fold-trigger, ward-truncate, child start/stop, and compile_and_load events. Evidence: `test/telemetry_test.exs` covers the registry and every documented event family; redaction-hit coverage is also pinned by a boundary `read_file` test. Commits `f08c847`, `c0fcc65`. |
| 12 | Dune sandbox over-restricts | **closed** | Dune is deliberate variant per #3 resolution. |
| 20 | Sandbox roots for filesystem gates | **closed** | `Cantrip.Gate.Path.validate/2` shared across all FS gates. Evidence: `test/gate_validation_test.exs:55-75`, `:99-133`. |
| 21 | Unbounded atom creation | **closed** | All paths bounded. Commits `d12875c`, `bc2bf01`, `80287b7`, `ca115b0`. |
| 22 | Reject unknown medium types | **closed** | `validate_known_medium/1` + bounded codomain. Evidence: `test/divergence_fixes_test.exs:110`. |
| 23 | cast_batch parallel contract | **closed** | `Task.async_stream/3` unconditional. Evidence: `test/composition_test.exs:37`, `test/readme_examples_test.exs:46+`. |
| 24 | Long-running runs in blocking GenServer.call | **closed** | Entity episodes now run in a monitored per-entity runner and reply via `GenServer.reply/2`; concurrent sends are rejected immediately while provider work continues, and code-medium port ownership survives across persistent sends. Evidence: `test/summon_test.exs` blocks provider work, proves a second `send/2` returns busy without waiting, then releases the original episode; the code-state test also asserts the same live port session survives a follow-up send. Commit `3ba8917`. |
| 25 | Multi-system messages Anthropic/Gemini | **closed** | Evidence: `test/req_llm_adapter_test.exs:177` (Anthropic), `:195` (Gemini). |
| 26 | README example drift | **closed** | Pinned by `test/readme_examples_test.exs`. Commit `05363e6`. |
| 27 | Parser-aware code-medium rewriting | **closed** | `add_dot_calls/2` now AST-based. Evidence: `test/code_medium_ergonomics_test.exs`. Commit `1d4e718`. |
| 30 | Malformed-JSON tool-call args | **closed** | `args_raw`+`args_decode_error` plumbing; executor emits structured error. Evidence: `test/req_llm_adapter_test.exs:106+`, `:136+`. |
| 31 | Mnesia create_schema error swallow | **closed** | `ensure_schema/0` propagates root cause. Evidence: `test/loom_storage_test.exs:20+`. |
| 32 | Schema version for durable structs + JSONL | **closed** | Durable/runtime structs now carry `schema_version: 1`; new JSONL loom files start with `{"format":"cantrip-loom","version":1}`; loader treats no-header files as legacy v1. Evidence: `test/schema_version_test.exs` covers struct versions; `test/loom_jsonl_persistence_test.exs` covers header creation and legacy no-header loading. Commit `d53b944`. |
| 34 | Pass 5: complete SafeFormat coverage at remaining boundary channels | **closed** | Boundary `inspect(...)` / `Exception.message(...)` sites now route through `Cantrip.SafeFormat` across gates, code-medium observations/protocol frames, ACP replies, CLI output, loom storage, child-cast observations/events, and provider adapter errors. Evidence: `test/redact_test.exs` covers non-binary gate output, unrestricted code-medium exceptions, ACP wire stringification, ACP runtime provider errors, JSONL persistence fallback, and port-medium exceptions; source scan shows no remaining raw boundary bypasses outside a static prompt example. Commit `4905898`. |
| 35 | compile_and_load: reject framework module names + handle deprecated allow_compile_namespaces | **closed** | `compile_and_load` now rejects attempts to hot-load modules shipped by the `:cantrip` application even when explicitly allowlisted, and deprecated `allow_compile_namespaces` wards fail loudly. Docs now describe exact `allow_compile_modules` semantics. Evidence: `test/hot_reload_test.exs` covers both policy gaps; focused tests and `mix verify` passed after rebase. Commit `7423ff0`. |
| 36 | Familiar cookie validation silently overwrites hand-edited cookies | **closed** | Workspace cookie policy now fails loud on invalid existing cookies and leaves the file unchanged. Evidence: `test/mix_cantrip_familiar_test.exs` covers generation with mode `0600`, reuse of valid existing cookies, and fail-loud/no-overwrite behavior for invalid hand-edited cookies. Commit `e013e85`. |

**Status legend:**
- `closed` — issue closed on GitHub with proof comment citing evidence
- `open, design-phase` — substantive defect, needs design before implementation
- `open, `feature`` — roadmap item, intentionally not in cleanup scope
- `open` — active cleanup work

---

## Per-Cleanup-Pass Status

| Pass | Topic | Status | Notes |
|---:|---|---|---|
| 0 | Baseline & inventory | **done** | v1.0.0 baseline + Pass 0 ripgrep scans complete (Pass 4/6/8/10). |
| 1 | Transformation safety | **done** | #27 AST rewrite shipped. No other regex-based source transforms in lib/. |
| 2 | Boundary / DTO integrity | **done** | #22 + #25 + #30 all closed with proof. |
| 3 | Atom safety | **done** | #21 closed; all paths bounded. |
| 4 | Configuration / ambient authority | **clean** | Pass 0 scan: 5 hits, all in boot/config paths. No hot-path violations. |
| 5 | Secret redaction & error sanitization | **done** | `Cantrip.SafeFormat` now covers boundary formatting across gate observations, code-medium observations/protocol frames, ACP replies, CLI output, loom storage, child-cast observations/events, and provider adapter errors. Evidence: `test/redact_test.exs` Pass 5 boundary formatting tests plus the source scan recorded in #34. |
| 6 | Unsafe deserialization / runtime eval | **clean** | Pass 0 scan: all `binary_to_term` uses `[:safe]` flag; `Code.eval_quoted` only in sandboxed port child. `compile_and_load` gated by exact-module allowlist. |
| 7 | OTP lifecycle / supervision | **done-for-tracked-issues** | #24 moved long-running entity episodes out of `handle_call/3` into a supervised, monitored per-entity runner. |
| 8 | Mailbox / backpressure | **clean** | Pass 0 scan: 0 `GenServer.cast`, 0 `handle_info`, raw `send/` only within supervised public API + port-child protocol. |
| 9 | GenServer functional-core cleanup | **done-for-tracked-issues** | #24 moved the main blocking workflow out of `EntityServer.handle_call/3` while keeping lifecycle and coordination in the GenServer. |
| 10 | Serialization / protocol / versioning | **done** | #32 closed with proof. Durable structs and JSONL loom format are versioned; no-header JSONL files load as legacy v1. |
| 11 | Persistence / state backend cleanup | **done** | #31 closed; Mnesia restart persistence verified. |
| 12 | Package / dependency boundaries | **done** | #3 closed (port surface proxies public API; Dune deliberate variant). |
| 13 | Observability / context propagation | **done** | #11 closed with proof. `docs/observability.md` and `Cantrip.Telemetry.events/0` are aligned and tested. |
| 14 | Idiomatic / performance | **not-needed-yet** | Late pass per guide; codebase is already idiomatic. |
| 15 | Final verification / governance lock-in | **deferred** | Final pass after all earlier passes done. |

---

## What's Left

No open cleanup items remain.

Plus three feature-roadmap items (`feature` label) that intentionally aren't blocking the cleanup-done milestone: #8, #9, #10.

The cleanup phase is done when final PR CI is green. At that point we can ship
v1.1.0 from `feat/comprehensive-cleanup`; the open issue tracker should contain
only the three intentionally-deferred feature items.

---

## Working agreements

- Every substantive commit gets a cold-reviewer-agent pass (claude lane).
- Every "close" cites a regression test or doc change in the comment.
- One cleanup-guide pass per commit going forward.
- `mix verify` green before commit, always.
- This file updates on commit (whoever ships, updates).
- GitHub ownership lives with claude (filing/closing/labeling); codex flags via scratch when an action is needed.
