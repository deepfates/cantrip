from __future__ import annotations

import argparse

from cantrip import Cantrip, Circle, FakeCrystal
from cantrip.cli import cmd_repl


def test_cmd_repl_prints_assistant_text_fallback(monkeypatch, capsys) -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {"tool_calls": [{"gate": "code", "args": {"source": "x"}}]},
                ],
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 2}]),
    )
    args = argparse.Namespace(
        repo_root=None,
        dotenv=".env",
        fake=False,
        code_runner=None,
        browser_driver=None,
    )
    inputs = iter(["hi", ":q"])

    monkeypatch.setattr("cantrip.cli.build_cantrip_from_env", lambda **_: cantrip)
    monkeypatch.setattr("builtins.input", lambda _prompt: next(inputs))

    rc = cmd_repl(args)
    out = capsys.readouterr().out

    assert rc == 0
    assert "No final answer produced. Last error: gate not available" in out
    assert "[tool:code] error" in out


class _FailingServer:
    def __init__(self, _cantrip) -> None:
        pass

    def create_session(self) -> str:
        return "s1"

    def cast(self, *, session_id: str, intent: str):
        raise TimeoutError("provider timed out")

    def close_session(self, _session_id: str) -> bool:
        return True


def test_cmd_repl_prints_structured_error_when_cast_raises(monkeypatch, capsys) -> None:
    args = argparse.Namespace(
        repo_root=None,
        dotenv=".env",
        fake=False,
        code_runner=None,
        browser_driver=None,
    )
    inputs = iter(["hi", ":q"])

    monkeypatch.setattr("cantrip.cli.build_cantrip_from_env", lambda **_: object())
    monkeypatch.setattr("cantrip.cli.CantripACPServer", _FailingServer)
    monkeypatch.setattr("builtins.input", lambda _prompt: next(inputs))

    rc = cmd_repl(args)
    out = capsys.readouterr().out

    assert rc == 0
    assert '"type": "internal_error"' in out
    assert '"error_type": "TimeoutError"' in out
    assert '"message": "provider timed out"' in out
