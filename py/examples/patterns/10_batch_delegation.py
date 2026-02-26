from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal


def run():
    parent = FakeCrystal(
        {
            "responses": [
                {"code": "var result = call_entity({intent: 'A'}); done(result);"}
            ]
        }
    )
    child = FakeCrystal(
        {
            "responses": [
                {"code": "done('A');"},
            ]
        }
    )
    c = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(
            gates=["done", "call_entity", "call_entity_batch"],
            wards=[{"max_turns": 5}, {"max_depth": 1}],
            medium="code",
        ),
    )
    return {
        "pattern": 10,
        "result": c.cast("batch"),
        "note": "single-child delegation baseline",
    }
