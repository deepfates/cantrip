from __future__ import annotations

from .common import mk_basic_cantrip


def run():
    fs = {"/data/test.txt": "hello world"}
    c = mk_basic_cantrip(
        [
            {"tool_calls": [{"gate": "read", "args": {"path": "test.txt"}}]},
            {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]},
        ],
        gates=[{"name": "done"}, {"name": "read", "depends": {"root": "/data"}}],
        filesystem=fs,
    )
    _r, t = c._cast_internal(intent="agent")
    return {"pattern": 12, "read": t.turns[0].observation[0].result}
