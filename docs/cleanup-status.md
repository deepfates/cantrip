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

**13 of 16 starting issues closed with proof. 1 new issue filed (#32 Pass 10
versioning). 3 feature-roadmap issues labeled `feature` and kept open. 2
active cleanup issues remain (#11, #32).**

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
| 5 | Secret redaction & error sanitization | **done** | `Cantrip.SafeFormat` + wiring to adapter errors, JSONL inspect fallbacks, port code-medium error surfaces. Commit `075878a`. |
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

Two open cleanup items, in priority order:

1. **#32 schema versioning** — forward-prep, not blocking anything. Add `schema_version: 1` to durable structs + JSONL header. Codex lane when scheduled.
2. **#11 telemetry coverage** — Pass 13 scope. Substantive design + implementation pass on its own. Lower urgency than #32.

Plus three feature-roadmap items (`feature` label) that intentionally aren't blocking the cleanup-done milestone: #8, #9, #10.

---

## Working agreements

- Every substantive commit gets a cold-reviewer-agent pass (claude lane).
- Every "close" cites a regression test or doc change in the comment.
- One cleanup-guide pass per commit going forward.
- `mix verify` green before commit, always.
- This file updates on commit (whoever ships, updates).
- GitHub ownership lives with claude (filing/closing/labeling); codex flags via scratch when an action is needed.
