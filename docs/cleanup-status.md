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

**As of 2026-05-28T23:57:47Z, the post-v1.2 stabilization queue remains
empty after v1.3.2.**

- Open GitHub issues: **0**.
- Open GitHub PRs: **0**.
- Latest tagged release: **v1.3.2** on `a3666dc`, tagged at
  2026-05-28T23:57:47Z.
- Latest stabilization merge: PR #106, `a3666dc`, `chore: prepare v1.3.2
  release`.
- v1.3.2 package verification: fresh extracted Hex tar dogfood, stable
  real-LLM suite, `mix verify`, `mix docs`, and `mix hex.build`.
- v1.3.0 shipped at 2026-05-28T17:29Z (`c71b0d7`, tag `v1.3.0`) and
  was superseded by v1.3.1 after two post-tag safety defects were found:
  #92 observation args could persist unredacted credential-shaped values,
  and #93 unknown code sandbox ward values fell back to unrestricted eval.
  Both were fixed in PR #94.
- v1.3.2 superseded v1.3.1 as the package-coherence release: README,
  Spellbook, ExDoc, public module voice, Familiar orientation, generated docs,
  and Hex package contents now describe the Elixir package as the canonical
  project.

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

v1.3.0 tagged at 17:29Z; safety defects #92 + #93 (found by adversarial
reviewer, not by audit-pass scans) were discovered at 17:34Z and fixed in
v1.3.1. The lesson: "all cleanup-guide passes done" claim still doesn't
mean "release-ready" — adversarial code-reading catches a different class
of defect than scan-based audits.

### Reward-Hack Honest Assessment (added 2026-05-28T17:54Z)

Post-tag rigorous re-examination of today's PRs surfaced a confirmation-
bias pattern in the claude-observed → codex-fixed → test-verifies-pattern
loop. Several closures match this shape:

- **PR #90** (Familiar composition teaching, closing #83) — partial.
  Methodological criticism stands: the in-CI FakeLLM test grades rigged
  scenarios tautologically rather than measuring real-LLM behavior under
  the new prompt. Prompt text additions came from claude's specific
  REPL failure modes. BUT: codex ran a scratch live-LLM A/B probe on
  the #83 synthesis user story (current prompt vs prompt-with-PR-#90-
  paragraphs-removed); the without-paragraphs version reproduced the
  data-dump failure (`PATH: module.ex` + raw source), with-paragraphs
  version produced synthesized prose using a conversation child. Single
  data point but directly on the motivating user story — falsifies the
  strongest version of "zero behavioral evidence." Codex's decision:
  keep the prompt change in v1.3.1; consider a gated real-LLM composition
  eval as future evidence; don't claim the FakeLLM test is behavioral
  proof.
- **PR #67 / #74** (loom code_state delta compaction, closing #67) —
  partial. Claude's observed 130KB record had 65KB code_state AND 65KB
  observation. Fix addresses binding-reuse compaction; observation-bloat
  half wasn't addressed because claude framed it as binding-only. Test
  pins claude's specific 50KB-binding-reuse pattern.
- **PR #82 / #84** (bash workload contract, closing #82) — partial.
  Workload suite (git + jq + make + find/sed/grep, three of four using
  /dev/null redirects) skewed toward claude's specific observation
  (`git log -1 --stat` with /dev/null). L2 framing was sound; coverage
  of OTHER common shell workloads (python/pip, curl, etc.) absent.

Holds up under reward-hack pressure: DTOs (#76, #77), ward composition
(#73, #78), ExDoc allowlist (#89), .env.example (#88), version drift
(#91), the runtime-safety patches (#92, #93 via #94) — observable
independent metrics; fixes not pattern-matched to claude's observation
set.

The discipline lesson: a closing test of "the thing claude said is wrong
now passes a test constructed around the thing claude said is wrong" is
not the same as "the underlying behavior actually improved for real
users." Adversarial code-reading and real-LLM eval are different
instruments and produce different signal.

### What we'd do differently

For future observation-shaped findings (behavioral claims about
entity/LLM behavior, UX failures, "this feels wrong" patterns), the
healthier loop shape is:

1. claude flags concern as a weak claim: "observed X in N runs under Z
   conditions"
2. proposes the probe that would distinguish "real bug" from "narrow
   observation": e.g. live-LLM A/B between candidate fix and baseline
   prompt on the motivating user story, measuring [specific metric]
3. whoever has the eval discipline runs the probe
4. fix is calibrated to probe evidence, not to the observation that
   triggered the investigation

Codex's live A/B probe on PR #90 (current prompt vs prompt-with-#90-
paragraphs-removed) is the canonical example: the probe falsified the
strongest version of claude's reward-hack criticism while validating
the methodological half. That shape — observe, probe, calibrate — is
load-bearing; "observe, implement, both claim improvement" is the
reward-hack trap.

For structural findings (spec violations, missing files, version drift,
security defects visible in code-reading), the verification path is
grep + read; probe is overkill. The two loops are different and should
not be conflated.

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
| 15 | Final verification / governance lock-in | **done** | v1.3.2 verification is current; CI runs `scripts/check_cleanup_guide.sh` to keep the high-risk cleanup invariants durable. |

---

## Release Gates

The current post-v1.2 stabilization and package-coherence release head is
`a3666dc`.

Authoritative gates:

- Open GitHub issues after v1.3.2: `[]`.
- Open GitHub PRs after v1.3.2: `[]`.
- PR #106 `verify`: success. Its `live` job was skipped because pull requests
  run unit/package verification only.
- v1.3.2 tag verification: success.

Local gates run before the v1.3.2 release:

- Fresh extracted Hex tar dogfood outside the repo with live LLM
  configuration:
  - `mix deps.get`
  - `mix cantrip.cast "explain what a cantrip is"`
  - `mix cantrip.familiar "summarize the loom storage modules"`
- `RUN_REAL_LLM_TESTS=1` stable live/real integration suite: 20 tests,
  0 failures.
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
