from __future__ import annotations

import argparse
import io
import json

from cantrip.cli import cmd_pipe


class _PipeServer:
    def __init__(self, _cantrip) -> None:
        self._calls = 0

    def create_session(self) -> str:
        return "s1"

    def cast(self, *, session_id: str, intent: str):
        self._calls += 1
        if self._calls == 1:
            raise TimeoutError("provider timed out")
        return {
            "thread_id": "t1",
            "result": "ok",
            "events": [{"type": "final_response", "result": "ok", "thread_id": "t1"}],
        }

    def close_session(self, _session_id: str) -> bool:
        return True


def test_cmd_pipe_emits_structured_error_and_continues(monkeypatch, capsys) -> None:
    args = argparse.Namespace(
        repo_root=None,
        dotenv=".env",
        fake=False,
        code_runner=None,
        browser_driver=None,
        with_events=True,
    )

    monkeypatch.setattr("cantrip.cli.build_cantrip_from_env", lambda **_: object())
    monkeypatch.setattr("cantrip.cli.CantripACPServer", _PipeServer)
    monkeypatch.setattr("sys.stdin", io.StringIO("hi\nsecond\n:q\n"))

    rc = cmd_pipe(args)
    out_lines = [ln for ln in capsys.readouterr().out.splitlines() if ln.strip()]

    assert rc == 0
    assert len(out_lines) == 2

    first = json.loads(out_lines[0])
    assert first["intent"] == "hi"
    assert first["result"] is None
    assert first["thread_id"] is None
    assert first["error"]["type"] == "internal_error"
    assert first["error"]["error_type"] == "TimeoutError"
    assert first["events"][0]["type"] == "error"
    assert first["events"][0]["error"]["error_type"] == "TimeoutError"

    second = json.loads(out_lines[1])
    assert second["intent"] == "second"
    assert second["result"] == "ok"
    assert second["thread_id"] == "t1"
