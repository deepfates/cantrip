# Implementation Tracker

Last updated: 2026-02-24
Branch: `feat/production-runtime`

This is the working task board for remaining implementation work. Keep it current as tasks move.

## Workflow

1. Pick the next unchecked task in `Now`.
2. Implement with small, atomic commits.
3. Run the listed verification command(s).
4. Mark task complete and move to `Done`.

## Definition of Done

- Code merged locally in an atomic commit.
- Relevant tests pass.
- Docs updated for user-facing behavior changes.
- Tracker status updated.

## Now (P0/P1)

- [x] Finalize pattern operability polish.
  - Scope:
    - Tracked `scripts/run_patterns.sh` with executable bit.
    - Kept `PATTERNS.md` at repo root for top-level discoverability.
    - Documented script usage in `examples/patterns/README.md`.
  - Verify:
    - `bash scripts/run_patterns.sh`
    - `./scripts/run_nonlive_tests.sh -q tests/patterns/test_pattern_examples.py`

- [x] Clean repository hygiene for local/dev artifacts.
  - Scope:
    - Kept `.env` ignored and `.env.example` available.
    - Ignored `.tmp_familiar/` runtime artifacts.
    - Confirmed no runtime DB artifacts are staged.
  - Verify:
    - `git status --short`

- [x] Make capstone interactive path explicitly operable from docs.
  - Scope:
    - Verified command/examples across `docs/CAPSTONE_INTERACTIVE.md` and scripts.
    - Confirmed one happy-path command each for REPL, pipe, and ACP stdio.
  - Verify:
    - `./scripts/smoke_acp.sh`
    - `./scripts/run_nonlive_tests.sh -q tests/test_capstone_cli_modes.py tests/test_acp_stdio.py`

## Next (P2)

- [x] Harden entity capability wiring for interactive sessions.
  - Goal: avoid silent "gate not available" loops for expected capstone capabilities.
  - Verify:
    - Added executable test for fail-fast behavior on unavailable gates.
    - `./scripts/run_nonlive_tests.sh -q tests/test_acp_server.py tests/test_acp_stdio.py tests/test_capstone_cli_modes.py`

- [x] Expand pattern execution coverage beyond module imports.
  - Goal: validate script-level and module-level invocation semantics stay aligned.
  - Verify:
    - Added `tests/patterns/test_run_patterns_script.py`.
    - `./scripts/run_nonlive_tests.sh -q tests/patterns/test_run_patterns_script.py tests/patterns/test_pattern_examples.py`

- [x] Improve progress visibility in ACP sessions.
  - Goal: ensure update payloads are client-compatible and useful for Toad/Zed.
  - Verify:
    - Added progress summary chunk (`agent_message_chunk`) and `_meta.progress`.
    - `./scripts/run_nonlive_tests.sh -q tests/test_acp_stdio.py tests/test_capstone_cli_modes.py`
    - `./scripts/smoke_acp.sh . "hello"`

## Later (P3)

- [x] Add higher-signal live integration checks (real crystals/models).
  - Goal: validate meaningful behavioral invariants, not just transport plumbing.
  - Verify:
    - Strengthened assertions in `tests/test_integration_openai_compat_live.py`:
      - provider usage metadata shape
      - tool-call absence for text-only query
      - turn/usage invariants for done path
      - no unavailable-gate errors during live cast
    - `uv run pytest -q tests/test_integration_openai_compat_live.py`

- [x] Add end-to-end scenario tests for delegated entity workflows.
  - Goal: confirm repo-reading + child-entity orchestration path in one flow.
  - Verify:
    - Added `tests/test_end_to_end_delegation.py`.
    - `./scripts/run_nonlive_tests.sh -q tests/test_end_to_end_delegation.py`

- [x] Add release-quality docs index for runtime ops.
  - Goal: one place for setup, runbooks, and troubleshooting.
  - Verify:
    - Added `docs/README.md` as runtime operations index.

## Done

- [x] Canonicalized `depends` surface and removed legacy `dependencies`.
- [x] Removed legacy `call_agent` aliases in favor of `call_entity` gates.
- [x] Hardened ACP stdio payload and fallback output behavior.
- [x] Added capstone executable coverage (pipe/REPL/ACP).
- [x] Added non-live/live helper scripts and ACP smoke script.
