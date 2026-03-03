from __future__ import annotations

from cantrip import Cantrip, Circle, FakeLLM


def run():
    circle = Circle(gates=["done"], wards=[{"max_turns": 3}])
    c1 = Cantrip(FakeLLM({"responses": [{"tool_calls": [{"gate": "done", "args": {"answer": "a"}}]}]}), circle)
    c2 = Cantrip(FakeLLM({"responses": [{"tool_calls": [{"gate": "done", "args": {"answer": "b"}}]}]}), circle)
    return {"pattern": 6, "results": [c1.cast("x"), c2.cast("x")]}
