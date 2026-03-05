from __future__ import annotations

from .common import mk_basic_cantrip


def run():
    terminated = mk_basic_cantrip([{"tool_calls": [{"gate": "done", "args": {"answer": "done"}}]}])
    truncated = mk_basic_cantrip(
        [{"tool_calls": [{"gate": "echo", "args": {"text": "x"}}]}],
        gates=["done", "echo"],
        wards=[{"max_turns": 1}],
    )
    r1, t1 = terminated._cast_internal(intent="t1")
    _r2, t2 = truncated._cast_internal(intent="t2")
    return {"pattern": 2, "terminated": t1.terminated, "truncated": t2.truncated, "result": r1}
