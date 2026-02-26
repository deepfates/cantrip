#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import json
import os
import pty
import signal
import subprocess
import time
from pathlib import Path
from typing import Any


def _parse_toad_log(log_path: Path) -> dict[str, Any]:
    client_methods: list[str] = []
    agent_frames: list[dict[str, Any]] = []

    for raw in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("[client] "):
            payload = ast.literal_eval(line[len("[client] ") :])
            if isinstance(payload, dict) and isinstance(payload.get("method"), str):
                client_methods.append(payload["method"])
        elif line.startswith("[agent] "):
            body = line[len("[agent] ") :]
            try:
                agent_frames.append(json.loads(body))
            except Exception:  # noqa: BLE001
                pass

    return {
        "client_methods": client_methods,
        "agent_frames": agent_frames,
    }


def run_probe(agent_command: str, project_dir: Path, duration_s: float) -> int:
    log_dir = Path.home() / ".local" / "state" / "toad" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    before = {p.name for p in log_dir.glob("*.txt")}

    master_fd, slave_fd = pty.openpty()
    proc = subprocess.Popen(
        ["toad", "acp", agent_command, str(project_dir)],
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        close_fds=True,
    )
    os.close(slave_fd)

    started = time.time()
    ok = False
    error: dict[str, str] | None = None
    parsed: dict[str, Any] = {}
    log_path: Path | None = None

    try:
        time.sleep(duration_s)
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)

        after = sorted(log_dir.glob("*.txt"), key=lambda p: p.stat().st_mtime, reverse=True)
        created = [p for p in after if p.name not in before]
        if not created:
            raise RuntimeError(f"no new toad logs found in {log_dir}")

        log_path = created[0]
        parsed = _parse_toad_log(log_path)

        methods = parsed.get("client_methods") or []
        if "initialize" not in methods:
            raise AssertionError(f"toad log missing initialize in {methods}")
        if "session/new" not in methods:
            raise AssertionError(f"toad log missing session/new in {methods}")

        ok = True
    except Exception as e:  # noqa: BLE001
        error = {"type": e.__class__.__name__, "message": str(e)}
    finally:
        os.close(master_fd)

    out = {
        "ok": ok,
        "agent_command": agent_command,
        "project_dir": str(project_dir),
        "duration_s": duration_s,
        "elapsed_s": round(time.time() - started, 3),
        "log_path": str(log_path) if log_path else None,
        "client_methods": parsed.get("client_methods"),
        "agent_frames": parsed.get("agent_frames"),
    }
    if error:
        out["error"] = error
    print(json.dumps(out, indent=2))
    return 0 if ok else 1


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run toad ACP client briefly and validate handshake from toad logs"
    )
    parser.add_argument("--agent-command", required=True, help="Quoted command passed to `toad acp`")
    parser.add_argument("--project-dir", default=".", help="Project directory passed to `toad acp`")
    parser.add_argument("--duration-s", type=float, default=3.0, help="How long to keep toad running")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    return run_probe(args.agent_command, Path(args.project_dir).resolve(), args.duration_s)


if __name__ == "__main__":
    raise SystemExit(main())
