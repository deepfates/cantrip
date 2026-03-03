from __future__ import annotations

from cantrip import Cantrip, Circle, FakeLLM


def run():
    p = FakeLLM(
        {
            "responses": [
                {"code": "var result = call_entity({intent: 'level1'}); done(result);"}
            ]
        }
    )
    l1 = FakeLLM(
        {
            "responses": [
                {"code": "var result = call_entity({intent: 'level2'}); done(result);"}
            ]
        }
    )
    l2 = FakeLLM({"responses": [{"code": "done('deepest');"}]})
    c = Cantrip(
        llm=p,
        llms={"child_llm_l1": l1, "child_llm_l2": l2},
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 5}, {"max_depth": 2}],
            medium="code",
        ),
    )
    return {"pattern": 14, "result": c.cast("rec")}
