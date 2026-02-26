from __future__ import annotations

from .common import mk_basic_cantrip


def run():
    c = mk_basic_cantrip(
        [{"tool_calls": [{"gate": "fetch", "args": {"url": "http://x"}}]}],
        gates=["done", "fetch"],
        wards=[{"max_turns": 2}, {"remove_gate": "fetch"}],
    )
    _r, t = c._cast_internal(intent="ward")
    return {"pattern": 5, "is_error": t.turns[0].observation[0].is_error}
