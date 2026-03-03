from __future__ import annotations

from cantrip import Cantrip, Circle, FakeLLM


def run():
    parent = FakeLLM(
        {
            "responses": [
                {
                    "code": "var a = call_entity({intent: 'collect'}); var b = call_entity({intent: 'synthesize'}); done(a + '|' + b);"
                }
            ]
        }
    )
    child = FakeLLM(
        {
            "responses": [
                {"code": "done('collect-ok');"},
                {"code": "done('synthesize-ok');"},
            ]
        }
    )
    c = Cantrip(
        llm=parent,
        child_llm=child,
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 6}, {"max_depth": 1}],
            medium="code",
        ),
    )
    return {"pattern": 15, "result": c.cast("research")}
