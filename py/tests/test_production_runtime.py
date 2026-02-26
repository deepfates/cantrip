from __future__ import annotations

from pathlib import Path

from cantrip import Call, Cantrip, Circle
from cantrip.errors import CantripError
from cantrip.models import CrystalResponse, ToolCall
from cantrip.loom import Loom, SQLiteLoomStore
from cantrip.providers.fake import FakeCrystal


def test_sqlite_loom_persists_turns(tmp_path: Path) -> None:
    db = tmp_path / "loom.db"
    store = SQLiteLoomStore(db)
    loom = Loom(store=store)

    crystal = FakeCrystal(
        {"responses": [{"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]}]}
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
        call=Call(system_prompt="persist"),
        loom=loom,
    )

    result = cantrip.cast("hello")
    assert result == "ok"
    assert len(loom.turns) == 1

    # New connection can read the same data.
    check = SQLiteLoomStore(db)
    rows = check.conn.execute("SELECT COUNT(*) FROM turns").fetchone()[0]
    assert rows == 1


def test_retry_on_provider_error() -> None:
    crystal = FakeCrystal(
        {
            "responses": [
                {"error": {"status": 429, "message": "rate limited"}},
                {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]},
            ]
        }
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
        retry={"max_retries": 2, "retryable_status_codes": [429]},
    )
    assert cantrip.cast("x") == "ok"
    assert len(crystal.invocations) == 2


def test_retry_on_provider_timeout() -> None:
    class _TimeoutThenSuccessCrystal:
        def __init__(self) -> None:
            self.calls = 0

        def query(self, _messages, _tools, _tool_choice):
            self.calls += 1
            if self.calls == 1:
                raise CantripError("provider_timeout:slow upstream")
            return CrystalResponse(
                content=None,
                tool_calls=[ToolCall(id="c1", gate="done", args={"answer": "ok"})],
                usage={"prompt_tokens": 1, "completion_tokens": 1},
            )

    crystal = _TimeoutThenSuccessCrystal()
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
        retry={"max_retries": 1},
    )
    assert cantrip.cast("x") == "ok"
    assert crystal.calls == 2


def test_loom_thread_lookup_and_fork() -> None:
    crystal = FakeCrystal(
        {
            "responses": [
                {"tool_calls": [{"gate": "echo", "args": {"text": "A"}}]},
                {"tool_calls": [{"gate": "done", "args": {"answer": "orig"}}]},
            ]
        }
    )
    fork_crystal = FakeCrystal(
        {"responses": [{"tool_calls": [{"gate": "done", "args": {"answer": "fork"}}]}]}
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 5}]),
    )
    result, thread = cantrip._cast_internal(intent="root")
    assert result == "orig"
    assert cantrip.loom.get_thread(thread.id) is not None
    assert len(cantrip.loom.list_threads()) >= 1

    fork_result, fork_thread = cantrip.fork(
        thread, from_turn=0, crystal=fork_crystal, intent="fork intent"
    )
    assert fork_result == "fork"
    assert len(fork_thread.turns) >= 2
