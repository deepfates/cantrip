from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal


def run():
    p = FakeCrystal(
        {
            "responses": [
                {"code": "var result = call_entity({intent: 'level1'}); done(result);"}
            ]
        }
    )
    l1 = FakeCrystal(
        {
            "responses": [
                {"code": "var result = call_entity({intent: 'level2'}); done(result);"}
            ]
        }
    )
    l2 = FakeCrystal({"responses": [{"code": "done('deepest');"}]})
    c = Cantrip(
        crystal=p,
        crystals={"child_crystal_l1": l1, "child_crystal_l2": l2},
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 5}, {"max_depth": 2}],
            medium="code",
        ),
    )
    return {"pattern": 14, "result": c.cast("rec")}
