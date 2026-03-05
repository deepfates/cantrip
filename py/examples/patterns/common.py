from __future__ import annotations

from pathlib import Path

from cantrip import (
    Identity,
    Cantrip,
    Circle,
    FakeLLM,
    InMemoryLoomStore,
    Loom,
    SQLiteLoomStore,
)


def mk_basic_cantrip(
    responses,
    *,
    gates=None,
    wards=None,
    identity=None,
    medium="tool",
    filesystem=None,
):
    llm = FakeLLM({"responses": responses})
    circle = Circle(
        gates=gates or ["done"],
        wards=wards or [{"max_turns": 5}],
        medium=medium,
        filesystem=filesystem,
    )
    return Cantrip(llm=llm, circle=circle, identity=identity or Identity())


def mk_sqlite_loom(tmp_dir: Path) -> Loom:
    store = SQLiteLoomStore(tmp_dir / "loom.db")
    return Loom(store=store)


def mk_memory_loom() -> Loom:
    return Loom(store=InMemoryLoomStore())
