from __future__ import annotations

from .common import mk_basic_cantrip


def run_service(intent: str):
    c = mk_basic_cantrip([{"tool_calls": [{"gate": "done", "args": {"answer": "service-ok"}}]}])
    return c.cast(intent)


def run():
    return {"pattern": 13, "result": run_service("hello")}
