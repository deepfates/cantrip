from __future__ import annotations

from .common import mk_basic_cantrip


def run():
    c = mk_basic_cantrip(
        [
            {"tool_calls": [{"gate": "echo", "args": {"text": "1"}}]},
            {"tool_calls": [{"gate": "echo", "args": {"text": "2"}}]},
            {"tool_calls": [{"gate": "echo", "args": {"text": "3"}}]},
            {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]},
        ],
        gates=["done", "echo"],
    )
    c.folding = {"trigger_after_turns": 2}
    _r, t = c._cast_internal(intent="fold")
    return {"pattern": 11, "turns": len(t.turns)}
