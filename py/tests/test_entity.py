"""Tests for the Entity (summon/send) pattern."""

from cantrip import Cantrip, Circle, FakeLLM
from cantrip.models import Identity


def test_summon_creates_entity() -> None:
    cantrip = Cantrip(
        llm=FakeLLM(
            {
                "responses": [
                    {"tool_calls": [{"gate": "done", "args": {"answer": "first"}}]},
                    {"tool_calls": [{"gate": "done", "args": {"answer": "second"}}]},
                ]
            }
        ),
        identity=Identity(system_prompt="test"),
        circle=Circle(gates=["done"], wards=[{"max_turns": 10}]),
    )
    entity = cantrip.summon()

    assert entity.entity_id
    assert entity.send("first task") == "first"
    assert entity.send("second task") == "second"
    assert len(entity.turns) > 0
