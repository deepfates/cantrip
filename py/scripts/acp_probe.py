#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def _recv_json_line(proc: subprocess.Popen[str], timeout_s: float) -> dict[str, Any]:
    assert proc.stdout is not None
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None:
                raise RuntimeError(f"agent exited early with code {proc.returncode}")
            time.sleep(0.01)
            continue
        line = line.strip()
        if not line:
            continue
        return json.loads(line)
    raise TimeoutError(f"timed out waiting for agent response after {timeout_s}s")


def _send(proc: subprocess.Popen[str], payload: dict[str, Any]) -> None:
    assert proc.stdin is not None
    proc.stdin.write(json.dumps(payload) + "\n")
    proc.stdin.flush()


def _send_and_expect_id(
    proc: subprocess.Popen[str], payload: dict[str, Any], timeout_s: float
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    expected_id = payload.get("id")
    if expected_id is None:
        raise ValueError("request payload must include id")

    _send(proc, payload)
    extras: list[dict[str, Any]] = []
    while True:
        frame = _recv_json_line(proc, timeout_s)
        if frame.get("id") == expected_id:
            return frame, extras
        extras.append(frame)


def _assert(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _session_id_from_new(frame: dict[str, Any]) -> str:
    result = frame.get("result") or {}
    sid = result.get("sessionId") or result.get("session_id")
    if not sid:
        raise AssertionError("session/new response missing sessionId")
    return str(sid)


def run_probe(cmd: list[str], prompt: str, timeout_s: float, method_style: str) -> int:
    if method_style == "dot":
        # ACP keeps initialize as a top-level method; dot style applies to session methods.
        init_method = "initialize"
        new_method = "session.new"
        prompt_method = "session.prompt"
    else:
        init_method = "initialize"
        new_method = "session/new"
        prompt_method = "session/prompt"

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    started = time.time()
    transcript: dict[str, Any] = {
        "command": cmd,
        "method_style": method_style,
        "requests": [],
        "responses": [],
        "notifications": [],
    }

    try:
        init_req = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": init_method,
            "params": {
                "protocolVersion": 1,
                "clientInfo": {"name": "acp_probe", "version": "1.0"},
                "clientCapabilities": {"terminal": True},
            },
        }
        transcript["requests"].append(init_req)
        init_resp, init_extras = _send_and_expect_id(proc, init_req, timeout_s)
        transcript["responses"].append(init_resp)
        transcript["notifications"].extend(init_extras)

        _assert("result" in init_resp, f"initialize returned error: {init_resp}")
        caps = (init_resp.get("result") or {}).get("capabilities") or {}
        _assert(
            bool(caps.get("session/prompt") or caps.get("session.prompt")),
            f"initialize capabilities missing session/prompt: {caps}",
        )

        new_req = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": new_method,
            "params": {"cwd": os.getcwd(), "mcpServers": []},
        }
        transcript["requests"].append(new_req)
        new_resp, new_extras = _send_and_expect_id(proc, new_req, timeout_s)
        transcript["responses"].append(new_resp)
        transcript["notifications"].extend(new_extras)

        _assert("result" in new_resp, f"session/new returned error: {new_resp}")
        session_id = _session_id_from_new(new_resp)

        prompt_req = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": prompt_method,
            "params": {
                "sessionId": session_id,
                "prompt": [{"type": "text", "text": prompt}],
            },
        }
        transcript["requests"].append(prompt_req)
        prompt_resp, prompt_extras = _send_and_expect_id(proc, prompt_req, timeout_s)
        transcript["responses"].append(prompt_resp)
        transcript["notifications"].extend(prompt_extras)

        _assert(
            "result" in prompt_resp, f"session/prompt returned error: {prompt_resp}"
        )
        out = (prompt_resp.get("result") or {}).get("output") or []
        _assert(isinstance(out, list), "session/prompt output is not a list")
        _assert(len(out) > 0, "session/prompt output is empty")

        elapsed_s = round(time.time() - started, 3)
        transcript["ok"] = True
        transcript["elapsed_s"] = elapsed_s
        print(json.dumps(transcript, indent=2))
        return 0
    except Exception as e:  # noqa: BLE001
        elapsed_s = round(time.time() - started, 3)
        transcript["ok"] = False
        transcript["elapsed_s"] = elapsed_s
        transcript["error"] = {"type": e.__class__.__name__, "message": str(e)}
        print(json.dumps(transcript, indent=2))
        return 1
    finally:
        try:
            proc.terminate()
        except Exception:  # noqa: BLE001
            pass
        try:
            proc.wait(timeout=1)
        except Exception:  # noqa: BLE001
            try:
                proc.kill()
            except Exception:  # noqa: BLE001
                pass


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe ACP stdio handshake and prompt")
    parser.add_argument(
        "--prompt",
        default="hello",
        help="Prompt text for session/prompt",
    )
    parser.add_argument(
        "--timeout-s",
        type=float,
        default=20.0,
        help="Timeout per expected response frame",
    )
    parser.add_argument(
        "--method-style",
        choices=["slash", "dot"],
        default="slash",
        help="Method naming style to test",
    )
    parser.add_argument(
        "command",
        nargs=argparse.REMAINDER,
        help="Command to run ACP stdio server (prefix with --)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cmd = list(args.command)
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        raise SystemExit("missing command; example: -- uv run cantrip --fake acp-stdio")
    return run_probe(cmd, args.prompt, args.timeout_s, args.method_style)


if __name__ == "__main__":
    raise SystemExit(main())
