# Post-v1 Cleanup Status

Living tracker for the post-v1 hardening and cleanup pass. Updated when the
issue queue or cleanup-pass state changes so the repo has a durable record that
does not require reading scratch notes.

**Working standard:** solve, do not administratively close. An issue leaves the
open set only when the underlying concern is gone and the repo contains
evidence: a regression test, a release gate, or a deliberate public contract
change.

**Sources:** GitHub issues and PRs (authoritative), the optional local
untracked `comprehensive_elixir_codebase_cleanup_guide.md` operator reference
when present, `scripts/check_cleanup_guide.sh`, and the v1.0.0 release commit
`9638ea2` as the cleanup baseline.

---

## Headline

**As of 2026-05-28T13:21:26Z, the post-v1.2 stabilization queue is empty.**

- Open GitHub issues: **0**.
- Open GitHub PRs at this snapshot (before opening this docs PR #80): **0**.
- Latest stabilization merge: PR #79, `779479b`, `fix: project bash gates through sandbox`.
- Main branch CI after PR #79: run `26577026692`, **success**.
- The full post-v1.2 audit queue (#41-#69) has shipped through focused PRs
  with regression coverage and release gates.

### What Changed Since v1.2.0

- **Pass 2 / boundary DTOs:** #48, #49, #52, #53, and #54 closed through PRs
  #66, #73, #76, and #77.
- **Pass 5 / redaction:** #63 closed through PR #70.
- **Pass 6 / runtime eval:** #43 closed through PR #79. Bash now projects gates
  into a sandboxed subprocess instead of presenting raw shell access as if it
  satisfied `A = M union G - W`.
- **Pass 7 and 8 / lifecycle and backpressure:** #60, #61, and #62 closed
  through PR #75.
- **Pass 10 and 11 / versioning and persistence:** #64, #65, and #67 closed
  through PRs #70, #71, and #74.
- **Pass 13 / observability:** #41, #42, #44, #45, #46, #47, #51, #55, #56,
  and #59 closed through PRs #50, #57, and #58.
- **Responsible recursion ward extension:** #69 closed through PR #78.
- **Default Familiar ergonomics:** #68 closed through PR #72.

### Rollback History

Commit `e747317` rolled back overclaimed "done" status once for passes 2, 7,
10, 13, and 15. The 2026-05-28 post-v1.2 re-audit rolled pass status back a
second time for passes 2, 6, 11, and 13. The final state below incorporates the
second audit and the subsequent fixes through PR #79.

The lesson is now part of the working standard: pass completion requires both
code evidence and an independent re-audit against the relevant guide criteria.

---

## Post-v1.2 Stabilization Issues

| Issue | Status | Evidence |
|---:|---|---|
| #41 | closed | PR #50 adds eval proof-of-purpose coverage. |
| #42 | closed | PR #50 propagates ACP trace context into entity events. |
| #43 | closed | PR #79 projects Bash gates through sandboxed commands and documents the new boundary. |
| #44 | closed | PR #57 forwards `tool_choice` into ReqLLM calls. |
| #45 | closed | PR #57 normalizes provider usage including `total_tokens`. |
| #46 | closed | PR #57 strengthens option-forwarding tests against the provider call seam. |
| #47 | closed | PR #58 exercises the real streaming `:text_delta` path. |
| #48 | closed | PR #73 composes parent wards for pre-built child casts. |
| #49 | closed | PR #66 preserves JSONL `truncation_reason` metadata. |
| #51 | closed | PR #58 removes raw-intent telemetry leakage and supersedes the original framing with #59. |
| #52 | closed | PR #66 constrains ACP `_meta` overrides. |
| #53 | closed | PR #76 introduces `%Cantrip.LLM.Response{}` at the provider boundary. |
| #54 | closed | PR #77 introduces per-gate args DTOs. |
| #55 | closed | PR #58 includes trace IDs in streaming envelopes. |
| #56 | closed | PR #58 preserves telemetry/redaction context across unrestricted eval tasks. |
| #59 | closed | PR #58 reinstates redacted `intent` telemetry. |
| #60 | closed | PR #75 adds streaming backpressure. |
| #61 | closed | PR #75 bounds ACP event bridge delivery through barrier sends. |
| #62 | closed | PR #75 shuts down cast-stream tasks on early halt and refreshes process inventory docs. |
| #63 | closed | PR #70 routes cross-node RPC errors through safe formatting. |
| #64 | closed | PR #70 aligns in-memory and durable loom append semantics. |
| #65 | closed | PR #71 adds event upcast behavior and serializes JSONL appends. |
| #67 | closed | PR #74 compacts persisted code-state bindings. |
| #68 | closed | PR #72 exposes `read_file` to the default Familiar. |
| #69 | closed | PR #78 adds declaration-time child-spawn wards. |

---

## Per-Cleanup-Pass Status

| Pass | Topic | Status | Current Evidence |
|---:|---|---|---|
| 0 | Baseline and inventory | **done** | v1.0.0 baseline identified; cleanup-guide scans are codified in `scripts/check_cleanup_guide.sh`. |
| 1 | Transformation safety | **done** | #27 replaced string-based code-medium rewriting with AST-aware handling. |
| 2 | Boundary / DTO integrity | **done** | Post-v1.2 gaps #48, #49, #52, #53, and #54 are closed. LLM responses and gate args now have explicit DTOs. |
| 3 | Atom safety | **done** | #21 closed; cleanup gate prevents new unbounded `String.to_atom` paths in production code. |
| 4 | Configuration / ambient authority | **clean** | Cleanup gate rejects hot-path `System.get_env` / `System.put_env`; PR #79 removed the Bash PATH regression caught by CI. |
| 5 | Secret redaction and error sanitization | **done** | #34 and #63 closed; boundary error formatting routes through safe formatting and redaction paths. |
| 6 | Unsafe deserialization / runtime eval | **done** | #43 closed by PR #79. Remaining runtime-eval exceptions are explicit, documented boundaries: port-child sandbox eval, the trusted unrestricted code medium, and compile-and-load allowlisted hot loading. |
| 7 | OTP lifecycle / supervision | **done** | #24 and #62 closed; entity work runs outside blocking GenServer calls and early stream halt shuts down runner tasks. |
| 8 | Mailbox / backpressure | **done** | #60 and #61 closed; streaming and ACP bridge delivery use bounded barrier behavior by default. |
| 9 | GenServer functional-core cleanup | **done** | `EntityServer` delegates runtime work to focused modules and supervised runner tasks. No open issue tracks hidden state or blocking callback work. |
| 10 | Serialization / protocol / versioning | **done** | #32 and #65 closed; durable structs and JSONL carry versioning/upcast behavior. |
| 11 | Persistence / state backend cleanup | **done** | #31, #64, #65, and #67 closed; loom append and JSONL write semantics are tested and documented. |
| 12 | Package / dependency boundaries | **done** | #3 and #12 closed; port medium proxies the public API while Dune remains a deliberate restricted variant. |
| 13 | Observability / context propagation | **done** | #41, #42, #44, #45, #46, #47, #51, #55, #56, and #59 closed; telemetry, streaming envelopes, and provider options preserve the intended context. |
| 14 | Idiomatic / performance | **clean** | No open cleanup issue remains in this pass. Existing regex and process-dictionary uses are bounded, documented patterns. |
| 15 | Final verification / governance lock-in | **done** | PR #79 and main push CI are green; CI runs `scripts/check_cleanup_guide.sh` to keep the high-risk cleanup invariants durable. |

---

## Release Gates

The final post-v1.2 stabilization head is `779479b`.

Authoritative gates:

- PR #79 `verify`: success.
- Main push run `26577026692`: success.
- Open GitHub issues after merge: `[]`.
- Open GitHub PRs after merge (before opening this docs PR #80): `[]`.

Local gates run on the final PR #79 head before merge:

- `mix test test/bash_medium_test.exs test/readme_examples_test.exs`
- `scripts/check_cleanup_guide.sh`
- `mix format --check-formatted` on changed Bash files
- `mix verify`
- `mix docs`
- `mix hex.build`

---

## What's Left

No release-blocking correctness, design, test, or documentation issue is
currently known in the GitHub tracker or the cleanup-guide ledger.

This does not mean the project is finished forever. It means the active
post-v1.2 stabilization queue has reached the requested stable empty state.
Future findings should be opened as new issues and worked through the same
solve-first PR loop.

---

## Working Agreements

- Every substantive change gets focused regression coverage or an explicit
  non-issue rationale.
- Cleanup-guide-sensitive commits run `scripts/check_cleanup_guide.sh`.
- Release candidates run `mix verify`, `mix docs`, and `mix hex.build`.
- PR comments should record review findings and the exact verification that
  supports merge readiness.
- GitHub issue closure follows the merge that actually removes the underlying
  concern.
