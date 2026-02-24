from __future__ import annotations

from pathlib import Path

from cantrip import (
    Call,
    Cantrip,
    Circle,
    FakeCrystal,
    InMemoryLoomStore,
    Loom,
    SQLiteLoomStore,
)


def mk_basic_cantrip(
    responses,
    *,
    gates=None,
    wards=None,
    call=None,
    medium="tool",
    filesystem=None,
):
    crystal = FakeCrystal({"responses": responses})
    circle = Circle(
        gates=gates or ["done"],
        wards=wards or [{"max_turns": 5}],
        medium=medium,
        filesystem=filesystem,
    )
    return Cantrip(crystal=crystal, circle=circle, call=call or Call())


def mk_sqlite_loom(tmp_dir: Path) -> Loom:
    store = SQLiteLoomStore(tmp_dir / "loom.db")
    return Loom(store=store)


def mk_memory_loom() -> Loom:
    return Loom(store=InMemoryLoomStore())
