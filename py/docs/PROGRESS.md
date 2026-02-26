# Progress Snapshot

Execution tracker: `docs/IMPLEMENTATION_TRACKER.md`

## Completed slices on `feat/production-runtime`

- Canonicalized configuration to `depends` across circle, gates, and child overrides.
- Hardened ACP stdio contract:
  - deterministic fallback assistant text for empty outcomes
  - strict `session/update` payload shape checks
  - ignore non-request JSON-RPC frames
- Expanded executable capstone mode coverage:
  - pipe mode
  - REPL mode
  - ACP stdio roundtrip
  - pipe `--with-events` schema assertions
- Added browser driver interface tests (resolver aliases, unknown errors, missing Playwright dependency surface).
- Removed legacy `call_agent` / `call_agent_batch` aliases; canonical gate names are `call_entity` / `call_entity_batch`.
- Added verification helpers:
  - `scripts/run_nonlive_tests.sh`
  - `scripts/run_all_tests.sh`
  - `scripts/smoke_acp.sh`

## Current verification status

- Non-live suite: `159 passed, 2 deselected`
- Live provider integration suite: `2 passed`
