from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAPSTONE = ROOT / "scripts" / "capstone.py"
PYTHON = ROOT / ".venv" / "bin" / "python"


def _python_exe() -> str:
    return str(PYTHON if PYTHON.exists() else Path(sys.executable))


def test_capstone_pipe_mode_emits_jsonl_result() -> None:
    proc = subprocess.run(
        [_python_exe(), str(CAPSTONE), "--fake", "--repo-root", str(ROOT)],
        input="hello\n",
        text=True,
        capture_output=True,
        check=True,
    )
    lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
    assert len(lines) == 1
    payload = json.loads(lines[0])
    assert payload["intent"] == "hello"
    assert payload["result"] == "fake-ok"
    assert payload["session_id"]
    assert payload["thread_id"]


def test_capstone_acp_stdio_mode_handles_prompt_roundtrip() -> None:
    proc = subprocess.Popen(
        [
            _python_exe(),
            str(CAPSTONE),
            "--fake",
            "--repo-root",
            str(ROOT),
            "--acp-stdio",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    assert proc.stdin is not None
    assert proc.stdout is not None

    def send(obj: dict) -> dict:
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()
        return json.loads(proc.stdout.readline().strip())

    init = send(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"protocolVersion": 1},
        }
    )
    assert init["id"] == 1
    assert init["result"]["capabilities"]["session/prompt"] is True

    new_sess = send({"jsonrpc": "2.0", "id": 2, "method": "session/new", "params": {}})
    sid = new_sess["result"]["sessionId"]

    proc.stdin.write(
        json.dumps(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "session/prompt",
                "params": {
                    "sessionId": sid,
                    "prompt": [{"type": "text", "text": "hi"}],
                },
            }
        )
        + "\n"
    )
    proc.stdin.flush()

    update_chunk = json.loads(proc.stdout.readline().strip())
    update_done = json.loads(proc.stdout.readline().strip())
    prompt_resp = json.loads(proc.stdout.readline().strip())
    proc.terminate()

    assert update_chunk["method"] == "session/update"
    assert update_chunk["params"]["update"]["sessionUpdate"] == "agent_message_chunk"
    assert update_done["method"] == "session/update"
    assert update_done["params"]["update"]["sessionUpdate"] == "agent_message"
    assert prompt_resp["id"] == 3
    assert prompt_resp["result"]["output"][0]["text"] == "fake-ok"


def test_capstone_repl_mode_handles_single_intent_and_quit() -> None:
    proc = subprocess.run(
        [_python_exe(), str(CAPSTONE), "--fake", "--repo-root", str(ROOT), "--repl"],
        input="hello\n:q\n",
        text=True,
        capture_output=True,
        check=True,
    )
    out = proc.stdout
    assert "session:" in out
    assert "enter an intent (`:q` to quit)" in out
    assert "result:" in out
    assert "fake-ok" in out


def test_capstone_pipe_mode_with_events_includes_step_and_final_events() -> None:
    proc = subprocess.run(
        [
            _python_exe(),
            str(CAPSTONE),
            "--fake",
            "--repo-root",
            str(ROOT),
            "--with-events",
        ],
        input="hello\n",
        text=True,
        capture_output=True,
        check=True,
    )
    lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
    assert len(lines) == 1
    payload = json.loads(lines[0])
    assert payload["result"] == "fake-ok"
    assert isinstance(payload["events"], list)
    kinds = [e.get("type") for e in payload["events"]]
    assert "step_start" in kinds
    assert "step_complete" in kinds
    assert "final_response" in kinds
