# Definition of Complete (Runtime + ACP)

Last updated: 2026-02-25

This is the operational completion contract for `cantrip-py`.  
Milestones can be implemented while this document is still not complete.

## 1) Runtime Semantics Coherence

Criteria:
- Code medium behavior is deterministic and aligned with `require_done_tool`.
- `done(answer)` is validated (no empty answer) and preserves intended result type.
- Delegation semantics (`call_entity`, `call_entity_batch`) remain stable under wards/depth.
- Non-live baseline is green.

Current status: `PASS`

Evidence:
- `./scripts/run_nonlive_tests.sh` -> `185 passed, 2 deselected`

## 2) ACP Real-Client Reliability

Criteria:
- Direct stdio handshake path succeeds: `initialize -> session/new -> session/prompt`.
- Real ACP client path succeeds (Toad).
- Zed path has reproducible frame-level evidence and no initialize dead-end.

Current status:
- Direct probe: `PASS`
- Toad probe: `PASS`
- Zed probe: `PASS` for wire-shape capture (`/tmp/cantrip_acp_zed.log`), real interactive Zed run still recommended during release checks.

Evidence:
- `./scripts/acp_probe.py --timeout-s 10 --method-style slash -- uv run cantrip --fake --repo-root . acp-stdio`
- `CANTRIP_ACP_TRANSPORT=legacy ./scripts/acp_probe.py --timeout-s 10 --method-style dot -- uv run cantrip --fake --repo-root . acp-stdio`
- `./scripts/toad_acp_probe.py --duration-s 2 --project-dir . --agent-command "<acp stdio command>"`

## 3) Structured Failure Semantics

Criteria:
- REPL/pipe/ACP return structured errors for provider/runtime failures.
- No crash-on-timeout behavior in REPL/pipe.
- Error categories are stable (`provider_timeout`, `provider_transport_error`, etc.).

Current status: `PASS` for CLI + ACP routing semantics  
Residual risk: live provider latency still appears as wait-without-progress in ACP clients.

Evidence:
- `tests/test_cli_repl.py`
- `tests/test_cli_pipe.py`
- `tests/test_provider_openai_compat.py`

## 4) Observability for Debugging

Criteria:
- ACP request/response/notify logging can be enabled at runtime.
- ACP result metadata includes timing summary for cast/turn/provider.
- Repro scripts exist for direct and client-level protocol checks.

Current status: `PASS`

Evidence:
- ACP debug env:
  - `CANTRIP_ACP_DEBUG=1`
  - `CANTRIP_ACP_DEBUG_FILE=/tmp/cantrip_acp_zed.log`
- Timing fields in ACP payload `_meta.timing`.
- Scripts:
  - `scripts/acp_probe.py`
  - `scripts/toad_acp_probe.py`
  - `scripts/acp_debug_log_summary.py`

## 5) Docs + Handoff Integrity

Criteria:
- Runbooks describe real commands used for verification.
- Completion status is explicit and not conflated with milestone completion.
- Next team can reproduce triage loop quickly.

Current status: `PASS`

---

## Execution Loop (keep using this)

1. Run baseline:
```bash
./scripts/run_nonlive_tests.sh
```

2. Run ACP probes:
```bash
./scripts/acp_probe.py --timeout-s 10 --method-style slash -- uv run cantrip --fake --repo-root . acp-stdio
CANTRIP_ACP_TRANSPORT=legacy ./scripts/acp_probe.py --timeout-s 10 --method-style dot -- uv run cantrip --fake --repo-root . acp-stdio
./scripts/toad_acp_probe.py --duration-s 2 --project-dir . --agent-command "<acp stdio command>"
```

3. Run Zed capture (manual interaction in Zed, then summarize):
```bash
./scripts/acp_debug_log_summary.py --log /tmp/cantrip_acp_zed.log
```

4. Run everything in one shot (writes `docs/COMPLETION_CHECK_REPORT.json`):
```bash
./scripts/run_completion_check.py
```
