from __future__ import annotations

from pathlib import Path

from cantrip import Identity, Cantrip, Circle, FakeLLM

from .common import mk_sqlite_loom


def run(tmp_dir: Path | None = None):
    base = tmp_dir or Path(".")
    loom = mk_sqlite_loom(base)
    familiar = Cantrip(
        llm=FakeLLM({"responses": [{"tool_calls": [{"gate": "done", "args": {"answer": "familiar-ok"}}]}]}),
        circle=Circle(gates=["done"], wards=[{"max_turns": 5}]),
        identity=Identity(system_prompt="You are a long-lived coordinator."),
        loom=loom,
    )
    return {"pattern": 16, "result": familiar.cast("coordinate"), "threads": len(familiar.loom.list_threads())}
