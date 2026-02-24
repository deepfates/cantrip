# Cantrip Runtime Ops Index

This is the operational index for running and verifying `cantrip-py`.

Tooling baseline: `uv` (scripts fall back to `./.venv/bin/*` when `uv` is unavailable).

## Quick Start

- Non-live verification:
  - `./scripts/run_nonlive_tests.sh`
- Full verification (includes live tests only when enabled):
  - `./scripts/run_all_tests.sh`
- ACP protocol smoke check:
  - `./scripts/smoke_acp.sh . "hello"`

## Interactive Runtime Modes

- Capstone interactive and service modes:
  - [CAPSTONE_INTERACTIVE.md](./CAPSTONE_INTERACTIVE.md)
  - Covers pipe, REPL, ACP stdio, and medium/runtime env vars.
  - Native CLI entrypoint: `cantrip` (`cantrip pipe|repl|acp-stdio`).

## Live Provider Testing

- Real crystal/provider setup:
  - [REAL_CRYSTAL_TESTING.md](./REAL_CRYSTAL_TESTING.md)
- Run live tests:
  - `CANTRIP_INTEGRATION_LIVE=1 ./scripts/run_live_tests.sh`

## Delivery Tracking

- Current implementation board:
  - [IMPLEMENTATION_TRACKER.md](./IMPLEMENTATION_TRACKER.md)
- Branch progress snapshot:
  - [PROGRESS.md](./PROGRESS.md)
- Milestone ledger:
  - [MILESTONES.md](./MILESTONES.md)

## Pattern Resources

- Spec-to-pattern narrative:
  - [PATTERN_PROGRESSION.md](./PATTERN_PROGRESSION.md)
- Pattern map in repo root:
  - `PATTERNS.md`
- Run pattern modules:
  - `bash scripts/run_patterns.sh`
