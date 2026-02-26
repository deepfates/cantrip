from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal
from cantrip.adapters import cast_via_acp, cast_via_cli, cast_via_http


def _build_tool_cantrip() -> Cantrip:
    crystal = FakeCrystal(
        {
            "record_inputs": True,
            "responses": [
                {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]},
            ],
        }
    )
    return Cantrip(
        crystal=crystal, circle=Circle(gates=["done"], wards=[{"max_turns": 3}])
    )


def _build_code_cantrip() -> Cantrip:
    crystal = FakeCrystal(
        {
            "record_inputs": True,
            "responses": [
                {"code": "done('ok');"},
            ],
        }
    )
    return Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}], medium="code"),
    )


def _snapshot_invocation(cantrip: Cantrip):
    inv = cantrip.crystal.invocations[0]
    return {
        "tool_choice": inv["tool_choice"],
        "tools": [t["name"] for t in inv["tools"]],
        "messages": [(m["role"], m["content"]) for m in inv["messages"]],
    }


def _assert_protocol_equivalence(build_cantrip, adapter) -> None:
    direct = build_cantrip()
    adapted = build_cantrip()

    direct_result = direct.cast("intent")
    adapted_result = adapter(adapted, "intent")

    assert adapted_result == direct_result
    assert _snapshot_invocation(adapted) == _snapshot_invocation(direct)


def test_protocol_wrappers_preserve_behavior_tool_circle() -> None:
    for adapter in (cast_via_cli, cast_via_http, cast_via_acp):
        _assert_protocol_equivalence(_build_tool_cantrip, adapter)


def test_protocol_wrappers_preserve_behavior_code_circle() -> None:
    for adapter in (cast_via_cli, cast_via_http, cast_via_acp):
        _assert_protocol_equivalence(_build_code_cantrip, adapter)
