from __future__ import annotations

from cantrip import Call

from .common import mk_basic_cantrip


def run():
    c = mk_basic_cantrip(
        [{"tool_calls": [{"id": "tc_1", "gate": "done", "args": {"answer": "ok"}}]}],
        call=Call(tool_choice="required"),
    )
    return {"pattern": 3, "result": c.cast("contract")}
