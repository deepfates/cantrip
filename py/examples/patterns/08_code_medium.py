from __future__ import annotations

from .common import mk_basic_cantrip


def run():
    c = mk_basic_cantrip(
        [{"code": "var x = 42;"}, {"code": "done(x);"}],
        gates=["done"],
        medium="code",
    )
    return {"pattern": 8, "result": c.cast("code")}
