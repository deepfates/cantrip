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
  - Uses `session/new` params `{"cwd":"<repo>","mcpServers":[]}` for ACP SDK compatibility.
- ACP protocol ground-truth probes:
  - `./scripts/acp_probe.py --timeout-s 10 --method-style slash -- uv run cantrip --fake --repo-root . acp-stdio`
  - `CANTRIP_ACP_TRANSPORT=legacy ./scripts/acp_probe.py --timeout-s 10 --method-style dot -- uv run cantrip --fake --repo-root . acp-stdio`
  - `./scripts/toad_acp_probe.py --duration-s 2 --project-dir . --agent-command "<your acp stdio command>"`
  - `./scripts/acp_debug_log_summary.py --log /tmp/cantrip_acp_zed.log`
  - `./scripts/run_completion_check.py` (one-shot full completion check; writes `docs/COMPLETION_CHECK_REPORT.json`)

## Interactive Runtime Modes

- Capstone interactive and service modes:
  - [CAPSTONE_INTERACTIVE.md](./CAPSTONE_INTERACTIVE.md)
  - Covers pipe, REPL, ACP stdio, and medium/runtime env vars.
  - Native CLI entrypoint: `cantrip` (`cantrip pipe|repl|acp-stdio`).
  - ACP transport default is SDK (`CANTRIP_ACP_TRANSPORT=sdk`); set `CANTRIP_ACP_TRANSPORT=legacy` to use the legacy adapter.

## Live Provider Testing

- Real crystal/provider setup:
  - [REAL_CRYSTAL_TESTING.md](./REAL_CRYSTAL_TESTING.md)
- Run live tests:
  - `CANTRIP_INTEGRATION_LIVE=1 ./scripts/run_live_tests.sh`

## Delivery Tracking

- Completion contract and readiness matrix:
  - [DEFINITION_OF_COMPLETE.md](./DEFINITION_OF_COMPLETE.md)
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
