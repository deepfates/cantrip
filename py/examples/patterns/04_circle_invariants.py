from __future__ import annotations

from cantrip import CantripError

from .common import mk_basic_cantrip


def run():
    try:
        mk_basic_cantrip([{"content": "x"}], gates=[], wards=[{"max_turns": 3}])
    except CantripError as e:
        return {"pattern": 4, "error": str(e)}
    return {"pattern": 4, "error": None}
