from __future__ import annotations

from .common import mk_basic_cantrip


def run():
    c = mk_basic_cantrip([{"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]}])
    return {"pattern": 1, "result": c.cast("say ok")}
