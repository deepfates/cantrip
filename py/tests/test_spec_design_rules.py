from __future__ import annotations

import pytest

from cantrip import Cantrip, Circle, FakeCrystal
from cantrip.acp_server import CantripACPServer
from cantrip.adapters import cast_via_acp, cast_via_cli, cast_via_http
from cantrip.cli_runner import run_cli
from cantrip.http_router import CantripHTTPRouter


def _build_tool_cantrip() -> Cantrip:
    return Cantrip(
        crystal=FakeCrystal(
            {
                "record_inputs": True,
                "responses": [
                    {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]},
                ],
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
    )


def _build_code_cantrip() -> Cantrip:
    return Cantrip(
        crystal=FakeCrystal(
            {
                "record_inputs": True,
                "responses": [
                    {"code": "done('ok');"},
                ],
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}], medium="code"),
    )


def _snapshot_first_query(cantrip: Cantrip) -> dict[str, object]:
    inv = cantrip.crystal.invocations[0]
    return {
        "tool_choice": inv["tool_choice"],
        "tools": [t["name"] for t in inv["tools"]],
        "messages": [(m["role"], m["content"]) for m in inv["messages"]],
    }


@pytest.mark.parametrize(
    "build_cantrip",
    [_build_tool_cantrip, _build_code_cantrip],
    ids=["tool_circle", "code_circle"],
)
def test_entity_1_only_cast_creates_entity_thread(build_cantrip) -> None:
    cantrip = build_cantrip()
    # Public API does not expose a freestanding Entity constructor.
    assert "Entity" not in __import__("cantrip").__all__
    # Creating a cantrip does not instantiate an entity/thread.
    assert cantrip.loom.list_threads() == []

    result, thread = cantrip.cast_with_thread("intent")
    assert result == "ok"
    assert thread.id
    assert len(cantrip.loom.list_threads()) == 1


@pytest.mark.parametrize(
    "build_cantrip",
    [_build_tool_cantrip, _build_code_cantrip],
    ids=["tool_circle", "code_circle"],
)
def test_prod_1_protocol_adapters_do_not_change_behavior(build_cantrip) -> None:
    def run_direct():
        c = build_cantrip()
        return c.cast("intent"), _snapshot_first_query(c)

    def run_cli_adapter():
        c = build_cantrip()
        return cast_via_cli(c, "intent"), _snapshot_first_query(c)

    def run_http_adapter():
        c = build_cantrip()
        return cast_via_http(c, "intent"), _snapshot_first_query(c)

    def run_acp_adapter():
        c = build_cantrip()
        return cast_via_acp(c, "intent"), _snapshot_first_query(c)

    def run_acp_server():
        c = build_cantrip()
        server = CantripACPServer(c)
        sid = server.create_session()
        payload = server.cast(session_id=sid, intent="intent")
        return payload["result"], _snapshot_first_query(c)

    def run_http_router():
        c = build_cantrip()
        router = CantripHTTPRouter(c)
        payload = router.handle_cast({"intent": "intent"})
        return payload["body"]["result"], _snapshot_first_query(c)

    def run_cli_runner():
        c = build_cantrip()
        payload = run_cli(c, intent="intent")
        return payload["result"], _snapshot_first_query(c)

    baseline_result, baseline_query = run_direct()
    for run in (
        run_cli_adapter,
        run_http_adapter,
        run_acp_adapter,
        run_acp_server,
        run_http_router,
        run_cli_runner,
    ):
        result, first_query = run()
        assert result == baseline_result
        assert first_query == baseline_query
