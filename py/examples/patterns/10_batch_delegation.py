from __future__ import annotations

from cantrip import Cantrip, Circle, FakeLLM


def run():
    parent = FakeLLM(
        {
            "responses": [
                {"code": "var result = call_entity({intent: 'A'}); done(result);"}
            ]
        }
    )
    child = FakeLLM(
        {
            "responses": [
                {"code": "done('A');"},
            ]
        }
    )
    c = Cantrip(
        llm=parent,
        child_llm=child,
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
