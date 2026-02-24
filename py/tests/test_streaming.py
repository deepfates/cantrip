from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal


def test_cast_stream_emits_final_response_event() -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]}
                ]
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
    )
    events = list(cantrip.cast_stream("x"))
    assert events
    assert events[-1]["type"] == "final_response"
    assert events[-1]["result"] == "ok"


def test_cast_stream_contains_step_and_tool_result_events() -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {"tool_calls": [{"gate": "echo", "args": {"text": "hello"}}]},
                    {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]},
                ]
            }
        ),
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 4}]),
    )
    events = list(cantrip.cast_stream("x"))
    kinds = [e["type"] for e in events]
    assert "step_start" in kinds
    assert "tool_result" in kinds
    assert "step_complete" in kinds
