from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal
from cantrip.http_router import CantripHTTPRouter


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
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
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


def _assert_cast_invariance(build_cantrip) -> None:
    direct = build_cantrip()
    via_router = build_cantrip()

    direct_result = direct.cast("intent")
    router = CantripHTTPRouter(via_router)
    resp = router.handle_cast({"intent": "intent"})
    assert resp["status"] == 200
    assert resp["body"]["result"] == direct_result
    assert _snapshot_invocation(via_router) == _snapshot_invocation(direct)


def test_http_router_cast_invariance_tool_circle() -> None:
    _assert_cast_invariance(_build_tool_cantrip)


def test_http_router_cast_invariance_code_circle() -> None:
    _assert_cast_invariance(_build_code_cantrip)


def test_http_router_validates_intent() -> None:
    router = CantripHTTPRouter(_build_tool_cantrip())
    resp = router.handle_cast({})
    assert resp["status"] == 400
    assert resp["body"]["error"]["code"] == "invalid_request"


def test_http_router_stream_returns_event_sequence() -> None:
    router = CantripHTTPRouter(_build_tool_cantrip())
    resp = router.handle_cast_stream({"intent": "intent"})
    assert resp["status"] == 200
    events = resp["body"]["events"]
    assert events
    assert events[-1]["type"] == "final_response"
