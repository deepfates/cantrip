from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal
from cantrip.acp_server import CantripACPServer
from cantrip.models import Call, Thread


def _build_tool_cantrip() -> Cantrip:
    crystal = FakeCrystal(
        {
            "record_inputs": True,
            "responses": [
                {"tool_calls": [{"gate": "echo", "args": {"text": "hi"}}]},
                {"tool_calls": [{"gate": "done", "args": {"answer": "ok"}}]},
            ],
        }
    )
    return Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 4}]),
    )


def _build_code_cantrip() -> Cantrip:
    crystal = FakeCrystal(
        {
            "record_inputs": True,
            "responses": [
                {"code": "var x = 1;"},
                {"code": "done('ok');"},
            ],
        }
    )
    return Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}], medium="code"),
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
    via_server = build_cantrip()

    direct_result = direct.cast("intent")
    server = CantripACPServer(via_server)
    session_id = server.create_session()
    payload = server.cast(session_id=session_id, intent="intent")

    assert payload["result"] == direct_result
    assert _snapshot_invocation(via_server) == _snapshot_invocation(direct)
    assert payload["thread_id"]
    assert payload["events"]
    assert payload["events"][-1]["type"] == "final_response"


def test_acp_server_cast_invariance_tool_circle() -> None:
    _assert_cast_invariance(_build_tool_cantrip)


def test_acp_server_cast_invariance_code_circle() -> None:
    _assert_cast_invariance(_build_code_cantrip)


def test_acp_server_rejects_unknown_session() -> None:
    server = CantripACPServer(_build_tool_cantrip())
    try:
        server.cast(session_id="missing", intent="intent")
    except KeyError as e:
        assert "unknown session" in str(e)
    else:
        raise AssertionError("expected KeyError for missing session")


def test_acp_server_session_lifecycle() -> None:
    server = CantripACPServer(_build_tool_cantrip())
    session_id = server.create_session()
    assert session_id
    assert server.session_exists(session_id) is True
    assert server.close_session(session_id) is True
    assert server.session_exists(session_id) is False
    assert server.close_session(session_id) is False


def test_acp_server_event_sequence_invariants() -> None:
    server = CantripACPServer(_build_tool_cantrip())
    sid = server.create_session()
    payload = server.cast(session_id=sid, intent="x")
    events = payload["events"]

    assert events[-1]["type"] == "final_response"
    assert [e["type"] for e in events].count("final_response") == 1

    step_starts = [e for e in events if e["type"] == "step_start"]
    step_completes = [e for e in events if e["type"] == "step_complete"]
    assert len(step_starts) == len(step_completes) >= 1

    # For each turn, boundaries are properly nested: start before complete.
    positions = {id(ev): i for i, ev in enumerate(events)}
    for start, done in zip(step_starts, step_completes):
        assert start["turn_id"] == done["turn_id"]
        assert positions[id(start)] < positions[id(done)]


def test_acp_server_preserves_session_history_in_followup_prompt() -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "record_inputs": True,
                "responses": [
                    {"tool_calls": [{"gate": "done", "args": {"answer": "first-ok"}}]},
                    {"tool_calls": [{"gate": "done", "args": {"answer": "second-ok"}}]},
                ],
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
    )
    server = CantripACPServer(cantrip)
    sid = server.create_session()

    first = server.cast(session_id=sid, intent="first question")
    second = server.cast(session_id=sid, intent="second question")

    assert first["result"] == "first-ok"
    assert second["result"] == "second-ok"
    second_messages = cantrip.crystal.invocations[1]["messages"]
    user_messages = [
        m.get("content", "") for m in second_messages if m.get("role") == "user"
    ]
    assert any("User: first question" in msg for msg in user_messages)
    assert any("User: second question" in msg for msg in user_messages)


def test_acp_server_events_include_only_new_turns_per_cast() -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {"tool_calls": [{"gate": "done", "args": {"answer": "first-ok"}}]},
                    {"tool_calls": [{"gate": "done", "args": {"answer": "second-ok"}}]},
                ],
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
    )
    server = CantripACPServer(cantrip)
    sid = server.create_session()

    first = server.cast(session_id=sid, intent="first question")
    second = server.cast(session_id=sid, intent="second question")

    first_steps = [e for e in first["events"] if e["type"] == "step_start"]
    second_steps = [e for e in second["events"] if e["type"] == "step_start"]

    assert len(first_steps) == 1
    assert len(second_steps) == 1


def test_acp_server_provides_fallback_assistant_text_when_result_is_none() -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {"tool_calls": [{"gate": "code", "args": {"source": "x"}}]},
                ],
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 2}]),
    )
    server = CantripACPServer(cantrip)
    sid = server.create_session()

    payload = server.cast(session_id=sid, intent="hi")

    assert payload["result"] == ""
    assert (
        payload["assistant_text"]
        == "No final answer produced. Last error: gate not available"
    )


def test_acp_server_stops_after_unavailable_gate_turn_instead_of_spinning() -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {"tool_calls": [{"gate": "code", "args": {"source": "x"}}]},
                    {"tool_calls": [{"gate": "code", "args": {"source": "x"}}]},
                    {"tool_calls": [{"gate": "code", "args": {"source": "x"}}]},
                ],
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 5}]),
    )
    server = CantripACPServer(cantrip)
    sid = server.create_session()

    payload = server.cast(session_id=sid, intent="hi")
    step_starts = [e for e in payload["events"] if e["type"] == "step_start"]
    tool_results = [e for e in payload["events"] if e["type"] == "tool_result"]

    assert payload["result"] == ""
    assert len(step_starts) == 1
    assert len(tool_results) == 1
    assert tool_results[0]["is_error"] is True
    assert tool_results[0]["content"] == "gate not available"


def test_acp_server_reports_error_when_done_answer_is_empty() -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {"code": "done('   ');"},
                ],
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 1}], medium="code"),
    )
    server = CantripACPServer(cantrip)
    sid = server.create_session()

    payload = server.cast(session_id=sid, intent="hi")
    tool_results = [e for e in payload["events"] if e["type"] == "tool_result"]

    assert payload["result"] is None
    assert len(tool_results) == 1
    assert tool_results[0]["is_error"] is True
    assert tool_results[0]["content"] == "missing required argument: answer"
    assert payload["assistant_text"].startswith(
        "No final answer produced before max_turns."
    )
    assert "Last error: missing required argument: answer" in payload["assistant_text"]
    assert payload["stop_reason"] == "max_turn_requests"


def test_acp_server_includes_timing_summary() -> None:
    server = CantripACPServer(_build_tool_cantrip())
    sid = server.create_session()

    payload = server.cast(session_id=sid, intent="x")
    timing = payload.get("timing")

    assert isinstance(timing, dict)
    assert timing["cast_ms"] >= 1
    assert timing["turns"] >= 1
    assert timing["turn_duration_ms"] >= 1
    assert "provider_latency_ms" in timing


def test_acp_server_maps_cancelled_thread_to_cancelled_stop_reason() -> None:
    cantrip = _build_tool_cantrip()
    server = CantripACPServer(cantrip)
    sid = server.create_session()

    def _cancelled_cast_with_thread(
        *, intent: str, seed_turns, event_sink=None, cancel_check=None
    ):  # noqa: ARG001
        thread = Thread(
            id="t-cancelled",
            entity_id="e",
            intent=intent,
            call=Call(),
            turns=[],
        )
        thread.truncated = True
        thread.__dict__["cancelled"] = True
        return None, thread

    cantrip.cast_with_thread = _cancelled_cast_with_thread  # type: ignore[method-assign]
    payload = server.cast(session_id=sid, intent="x")

    assert payload["stop_reason"] == "cancelled"
    assert payload["assistant_text"] == "Cancelled."


def test_acp_server_fails_fast_on_stagnant_code_loop() -> None:
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {"code": "x = 1"},
                    {"code": "x = 2"},
                    {"code": "x = 3"},
                    {"code": "x = 4"},
                    {"code": "done('ok')"},
                ]
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 8}], medium="code"),
        call=Call(require_done_tool=True, tool_choice="required"),
    )
    server = CantripACPServer(cantrip)
    sid = server.create_session()

    payload = server.cast(session_id=sid, intent="hi")
    tool_results = [e for e in payload["events"] if e["type"] == "tool_result"]

    assert payload["stop_reason"] == "end_turn"
    assert payload["assistant_text"].startswith("No final answer produced. Last error:")
    assert "non-terminal code loop detected" in payload["assistant_text"]
    assert any(
        ev.get("is_error") is True
        and ev.get("content") == "non-terminal code loop detected"
        for ev in tool_results
    )
