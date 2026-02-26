from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal


def run():
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "code": "var a = call_entity({intent: 'collect'}); var b = call_entity({intent: 'synthesize'}); done(a + '|' + b);"
                }
            ]
        }
    )
    child = FakeCrystal(
        {
            "responses": [
                {"code": "done('collect-ok');"},
                {"code": "done('synthesize-ok');"},
            ]
        }
    )
    c = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 6}, {"max_depth": 1}],
            medium="code",
        ),
    )
    return {"pattern": 15, "result": c.cast("research")}
