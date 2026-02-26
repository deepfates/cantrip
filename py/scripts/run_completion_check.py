#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            continue
        os.environ.setdefault(key, value.strip())


def _run(
    cmd: list[str], timeout: int = 240, env: dict[str, str] | None = None
) -> dict[str, Any]:
    t0 = time.time()
    try:
        p = subprocess.run(
            cmd,
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return {
            "ok": p.returncode == 0,
            "returncode": p.returncode,
            "elapsed_s": round(time.time() - t0, 3),
            "stdout": p.stdout,
            "stderr": p.stderr,
            "cmd": cmd,
        }
    except Exception as e:  # noqa: BLE001
        return {
            "ok": False,
            "returncode": None,
            "elapsed_s": round(time.time() - t0, 3),
            "stdout": "",
            "stderr": str(e),
            "cmd": cmd,
        }


def _json_from_stdout(raw: str) -> dict[str, Any] | None:
    raw = raw.strip()
    if not raw:
        return None
    try:
        return json.loads(raw)
    except Exception:  # noqa: BLE001
        return None


def _zed_log_signal() -> dict[str, Any]:
    zed_log = Path.home() / "Library" / "Logs" / "Zed" / "Zed.log"
    if not zed_log.exists():
        return {"ok": False, "reason": f"missing {zed_log}"}
    text = zed_log.read_text(encoding="utf-8", errors="replace")
    lines = [ln for ln in text.splitlines() if "agent_servers::acp" in ln]
    parse_errors = [
        ln for ln in text.splitlines() if "failed to parse incoming message" in ln
    ]
    return {
        "ok": True,
        "path": str(zed_log),
        "acp_log_lines": len(lines),
        "parse_errors": len(parse_errors),
        "last_parse_error": parse_errors[-1] if parse_errors else None,
    }


def _zed_log_delta(previous_size: int) -> dict[str, Any]:
    zed_log = Path.home() / "Library" / "Logs" / "Zed" / "Zed.log"
    if not zed_log.exists():
        return {"ok": False, "reason": f"missing {zed_log}"}
    data = zed_log.read_text(encoding="utf-8", errors="replace")
    delta = data[previous_size:] if previous_size < len(data) else ""
    parse_errors = [
        ln for ln in delta.splitlines() if "failed to parse incoming message" in ln
    ]
    mode_errors = [ln for ln in delta.splitlines() if "CurrentModeUpdate" in ln]
    return {
        "ok": True,
        "new_bytes": max(0, len(data) - previous_size),
        "new_parse_errors": len(parse_errors),
        "new_current_mode_errors": len(mode_errors),
        "last_new_parse_error": parse_errors[-1] if parse_errors else None,
        "last_new_mode_error": mode_errors[-1] if mode_errors else None,
    }


def main() -> int:
    _load_env_file(ROOT / ".env")
    zed_log = Path.home() / "Library" / "Logs" / "Zed" / "Zed.log"
    zed_size_before = zed_log.stat().st_size if zed_log.exists() else 0

    report: dict[str, Any] = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "cwd": str(ROOT),
        "checks": {},
    }

    checks = report["checks"]

    checks["nonlive_suite"] = _run(["./scripts/run_nonlive_tests.sh"], timeout=600)

    checks["acp_probe_slash_fake"] = _run(
        [
            "./scripts/acp_probe.py",
            "--timeout-s",
            "10",
            "--method-style",
            "slash",
            "--",
            "uv",
            "run",
            "cantrip",
            "--fake",
            "--repo-root",
            ".",
            "acp-stdio",
        ],
        timeout=120,
    )

    legacy_env = os.environ.copy()
    legacy_env["CANTRIP_ACP_TRANSPORT"] = "legacy"
    checks["acp_probe_dot_fake"] = _run(
        [
            "./scripts/acp_probe.py",
            "--timeout-s",
            "10",
            "--method-style",
            "dot",
            "--",
            "uv",
            "run",
            "cantrip",
            "--fake",
            "--repo-root",
            ".",
            "acp-stdio",
        ],
        timeout=120,
        env=legacy_env,
    )

    toad_cmd = (
        f"{ROOT}/.venv/bin/python {ROOT}/scripts/capstone.py "
        f"--fake --acp-stdio --repo-root {ROOT} --dotenv {ROOT}/.env"
    )
    checks["toad_probe_fake"] = _run(
        [
            "./scripts/toad_acp_probe.py",
            "--duration-s",
            "2",
            "--project-dir",
            ".",
            "--agent-command",
            toad_cmd,
        ],
        timeout=120,
    )

    # Live probe only if env is configured.
    live_env_ok = bool(
        os.getenv("CANTRIP_OPENAI_MODEL") and os.getenv("CANTRIP_OPENAI_BASE_URL")
    )
    if live_env_ok:
        env = os.environ.copy()
        env.setdefault("CANTRIP_OPENAI_TIMEOUT_S", "20")
        checks["acp_probe_slash_live"] = _run(
            [
                "./scripts/acp_probe.py",
                "--timeout-s",
                "25",
                "--method-style",
                "slash",
                "--",
                "uv",
                "run",
                "cantrip",
                "--repo-root",
                ".",
                "acp-stdio",
            ],
            timeout=180,
            env=env,
        )
    else:
        checks["acp_probe_slash_live"] = {
            "ok": False,
            "skipped": True,
            "reason": "missing CANTRIP_OPENAI_MODEL or CANTRIP_OPENAI_BASE_URL",
        }

    zed_debug_log = Path("/tmp/cantrip_acp_zed.log")
    if zed_debug_log.exists():
        checks["zed_debug_summary"] = _run(
            ["./scripts/acp_debug_log_summary.py", "--log", str(zed_debug_log)],
            timeout=30,
        )
    else:
        debug_env = os.environ.copy()
        debug_env["CANTRIP_ACP_DEBUG"] = "1"
        debug_env["CANTRIP_ACP_DEBUG_FILE"] = str(zed_debug_log)
        checks["zed_debug_generate"] = _run(
            [
                "./scripts/acp_probe.py",
                "--timeout-s",
                "10",
                "--method-style",
                "slash",
                "--",
                "uv",
                "run",
                "cantrip",
                "--fake",
                "--repo-root",
                ".",
                "acp-stdio",
            ],
            timeout=120,
            env=debug_env,
        )
        if zed_debug_log.exists():
            checks["zed_debug_summary"] = _run(
                ["./scripts/acp_debug_log_summary.py", "--log", str(zed_debug_log)],
                timeout=30,
            )
            checks["zed_debug_summary"]["synthetic_source"] = True
        else:
            checks["zed_debug_summary"] = {
                "ok": False,
                "skipped": True,
                "reason": f"missing {zed_debug_log}",
            }

    checks["zed_log_signal"] = _zed_log_signal()
    checks["zed_log_delta"] = _zed_log_delta(zed_size_before)

    # Parse JSON payloads where available.
    for key, value in list(checks.items()):
        if isinstance(value, dict) and isinstance(value.get("stdout"), str):
            parsed = _json_from_stdout(value["stdout"])
            if parsed is not None:
                value["parsed"] = parsed

    critical_keys = [
        "nonlive_suite",
        "acp_probe_slash_fake",
        "acp_probe_dot_fake",
        "toad_probe_fake",
    ]
    critical_ok = all(bool(checks.get(k, {}).get("ok")) for k in critical_keys)

    report["summary"] = {
        "critical_ok": critical_ok,
        "zed_debug_captured": bool(checks.get("zed_debug_summary", {}).get("ok")),
        "live_probe_ok": bool(checks.get("acp_probe_slash_live", {}).get("ok")),
    }

    out_path = ROOT / "docs" / "COMPLETION_CHECK_REPORT.json"
    out_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))

    return 0 if critical_ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
