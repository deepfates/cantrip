from __future__ import annotations

from .common import mk_basic_cantrip


def run():
    c = mk_basic_cantrip([
        {"tool_calls": [{"gate": "echo", "args": {"text": "hello"}}]},
        {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]},
    ], gates=["done", "echo"])
    return {"pattern": 7, "result": c.cast("chat")}
