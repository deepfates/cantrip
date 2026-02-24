from __future__ import annotations

import time

from cantrip import Cantrip, Circle, FakeCrystal


def test_code_circle_projects_single_code_tool_and_required_choice() -> None:
    crystal = FakeCrystal(
        {
            "record_inputs": True,
            "responses": [
                {"code": "done('ok');"},
            ],
        }
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(
            gates=["done", "echo"], wards=[{"max_turns": 3}], medium="code"
        ),
    )
    assert cantrip.cast("run code") == "ok"

    inv = crystal.invocations[0]
    assert inv["tool_choice"] == "required"
    assert [t["name"] for t in inv["tools"]] == ["code"]
    assert inv["tools"][0]["parameters"]["required"] == ["code"]


def test_call_entity_gate_name_supported_in_code_circle() -> None:
    parent = FakeCrystal(
        {
            "responses": [
                {"code": "var r = call_entity({intent: 'child'}); done(r);"},
            ]
        }
    )
    child = FakeCrystal({"responses": [{"code": "done('child-ok');"}]})
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 5}, {"max_depth": 1}],
            medium="code",
        ),
    )
    assert cantrip.cast("parent") == "child-ok"


def test_call_entity_batch_runs_children_concurrently() -> None:
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "code": (
                        "var r = call_entity_batch([{intent:'a'},{intent:'b'},{intent:'c'}]);"
                        'done(r.join(","));'
                    )
                }
            ]
        }
    )
    child = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {"gate": "slow_gate", "args": {}},
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                },
                {
                    "tool_calls": [
                        {"gate": "slow_gate", "args": {}},
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                },
                {
                    "tool_calls": [
                        {"gate": "slow_gate", "args": {}},
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                },
            ]
        }
    )
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(
            gates=[
                "done",
                "call_entity",
                "call_entity_batch",
                {"name": "slow_gate", "delay_ms": 200},
            ],
            wards=[{"max_turns": 5}, {"max_depth": 1}],
            medium="code",
        ),
    )
    # Sequential would be about 0.6s (3 x 200ms); concurrent should be much lower.
    t0 = time.perf_counter()
    result = cantrip.cast("parent")
    elapsed = time.perf_counter() - t0

    assert result == "ok,ok,ok"
    assert elapsed < 0.45


def test_code_circle_accepts_code_function_tool_calls() -> None:
    crystal = FakeCrystal(
        {
            "responses": [
                {"tool_calls": [{"gate": "code", "args": {"code": "done('ok');"}}]},
            ]
        }
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}], medium="code"),
    )
    assert cantrip.cast("run") == "ok"


def test_code_circle_records_error_for_empty_code_tool_call() -> None:
    crystal = FakeCrystal(
        {
            "responses": [
                {"tool_calls": [{"gate": "code", "args": {}}]},
            ]
        }
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 1}], medium="code"),
    )
    result, thread = cantrip.cast_with_thread("run")
    assert result is None
    assert len(thread.turns) == 1
    assert thread.turns[0].observation[0].is_error is True
    assert thread.turns[0].observation[0].content == "missing code/source/input"
