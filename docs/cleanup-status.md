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
cookie overwrite. #34 is closed with proof. 3 feature-roadmap issues labeled
`feature` and kept open. 4 active cleanup issues remain (#11, #32, #35, #36).**

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
| 11 | Telemetry coverage + observability runbook | **open** | Pass 13 work. Substantive design + impl scope. |
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
| 32 | Schema version for durable structs + JSONL | **open** | Filed post-Pass-0-scan. 8 defstructs lack version field; JSONL has no format header. Forward-prep, not active bug. |
| 34 | Pass 5: complete SafeFormat coverage at remaining boundary channels | **closed** | Boundary `inspect(...)` / `Exception.message(...)` sites now route through `Cantrip.SafeFormat` across gates, code-medium observations/protocol frames, ACP replies, CLI output, loom storage, child-cast observations/events, and provider adapter errors. Evidence: `test/redact_test.exs` covers non-binary gate output, unrestricted code-medium exceptions, ACP wire stringification, ACP runtime provider errors, JSONL persistence fallback, and port-medium exceptions; source scan shows no remaining raw boundary bypasses outside a static prompt example. Commit `4905898`. |
| 35 | compile_and_load: reject framework module names + handle deprecated allow_compile_namespaces | **open** | Cold-review of `ca115b0` found two concerns: gate doesn't reject `Elixir.Cantrip.*` modules in allowlists, and `allow_compile_namespaces` is silently ignored (permission broadening relative to caller intent). Doc drift in `DEPLOYMENT.md:200`. |
| 36 | Familiar cookie validation silently overwrites hand-edited cookies | **open** | Cold-review of `bc2bf01`. `validate_or_regenerate_cookie` silently regenerates non-matching cookies, breaking existing distributed connections without warning. Either log on overwrite or hard-fail and require explicit deletion. |

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
| 10 | Serialization / protocol / versioning | **issue-filed** | #32 captures the gap. Forward-prep work. |
| 11 | Persistence / state backend cleanup | **done** | #31 closed; Mnesia restart persistence verified. |
| 12 | Package / dependency boundaries | **done** | #3 closed (port surface proxies public API; Dune deliberate variant). |
| 13 | Observability / context propagation | **issue-open** | #11 covers this entirely. |
| 14 | Idiomatic / performance | **not-needed-yet** | Late pass per guide; codebase is already idiomatic. |
| 15 | Final verification / governance lock-in | **deferred** | Final pass after all earlier passes done. |

---

## What's Left

Four open cleanup items, in priority order:

1. **#35 compile_and_load policy gaps** — reject framework module names; handle deprecated `allow_compile_namespaces` either with deprecation warning or explicit validation error; update `DEPLOYMENT.md` doc drift. Codex lane.
2. **#11 telemetry coverage** — implementation against the contract in `docs/observability.md`. Trace_id propagation + 7 missing events + per-event regression tests. Codex lane.
3. **#32 schema versioning** — forward-prep, not blocking anything. Add `schema_version: 1` to durable structs + JSONL header. Codex lane when scheduled.
4. **#36 cookie overwrite** — small, operator-experience fix. Either log on regeneration or hard-fail. Codex lane.

Plus three feature-roadmap items (`feature` label) that intentionally aren't blocking the cleanup-done milestone: #8, #9, #10.

The cleanup phase reaches "done" when #35, #11, #32, #36 land and `mix verify` stays green. Then we ship a v1.1.0 from `feat/comprehensive-cleanup` and the open issue tracker has only the three intentionally-deferred feature items.

---

## Working agreements

- Every substantive commit gets a cold-reviewer-agent pass (claude lane).
- Every "close" cites a regression test or doc change in the comment.
- One cleanup-guide pass per commit going forward.
- `mix verify` green before commit, always.
- This file updates on commit (whoever ships, updates).
- GitHub ownership lives with claude (filing/closing/labeling); codex flags via scratch when an action is needed.
