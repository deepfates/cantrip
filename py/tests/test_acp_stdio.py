from __future__ import annotations

import json
from io import StringIO

import cantrip.acp_server as acp_server_mod
from cantrip import Cantrip, Circle, FakeCrystal
from cantrip.acp_stdio import ACPStdioRouter, serve_stdio, serve_stdio_once


def _build_cantrip() -> Cantrip:
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


def test_router_create_session_and_cast() -> None:
    router = ACPStdioRouter(_build_cantrip())
    create_resp = router.handle({"id": "1", "method": "session.create"})
    assert create_resp["id"] == "1"
    session_id = create_resp["result"]["session_id"]

    cast_resp = router.handle(
        {
            "id": "2",
            "method": "cast",
            "params": {"session_id": session_id, "intent": "hello"},
        }
    )
    assert cast_resp["id"] == "2"
    assert cast_resp["result"]["result"] == "ok"
    assert cast_resp["result"]["thread_id"]


def test_router_session_prompt_alias_accepts_text_blocks() -> None:
    router = ACPStdioRouter(_build_cantrip())
    create_resp = router.handle({"id": "1", "method": "session/new"})
    session_id = create_resp["result"]["sessionId"]
    prompt_resp = router.handle(
        {
            "id": "2",
            "method": "session/prompt",
            "params": {
                "sessionId": session_id,
                "prompt": [{"type": "text", "text": "hello"}],
            },
        }
    )
    assert prompt_resp["id"] == "2"
    assert prompt_resp["result"]["stopReason"] == "end_turn"
    assert prompt_resp["result"]["_meta"]["sessionId"] == session_id
    assert prompt_resp["result"]["_meta"]["result"] == "ok"
    assert prompt_resp["result"]["_meta"]["progress"]["steps"] >= 1
    assert prompt_resp["result"]["_meta"]["progress"]["tool_calls"] >= 1
    assert prompt_resp["result"]["_meta"]["timing"]["cast_ms"] >= 1
    assert prompt_resp["result"]["_meta"]["timing"]["turns"] >= 1


def test_router_session_prompt_dot_alias_emits_notifications() -> None:
    router = ACPStdioRouter(_build_cantrip())
    create_resp = router.handle({"id": "1", "method": "session.new"})
    session_id = create_resp["result"]["sessionId"]
    req = {
        "id": "2",
        "method": "session.prompt",
        "params": {
            "sessionId": session_id,
            "prompt": [{"type": "text", "text": "hello"}],
        },
    }
    prompt_resp = router.handle(req)
    updates = router.notifications_for(req, prompt_resp)

    assert prompt_resp["result"]["stopReason"] == "end_turn"
    assert [u["params"]["update"]["sessionUpdate"] for u in updates] == [
        "agent_message_chunk",
        "agent_message",
    ]


def test_router_initialize_and_authenticate() -> None:
    router = ACPStdioRouter(_build_cantrip())
    init_resp = router.handle(
        {"id": "i", "method": "initialize", "params": {"protocolVersion": 1}}
    )
    assert init_resp["id"] == "i"
    assert init_resp["result"]["protocolVersion"] == 1
    assert init_resp["result"]["agentInfo"]["name"] == "cantrip-py"
    assert init_resp["result"]["capabilities"]["session/prompt"] is True
    assert init_resp["result"]["capabilities"]["session.prompt"] is True
    assert init_resp["result"]["agentCapabilities"]["loadSession"] is False
    assert (
        init_resp["result"]["agentCapabilities"]["promptCapabilities"]["image"] is False
    )
    assert init_resp["result"]["agentCapabilities"]["defaultModeId"] == "default"
    assert init_resp["result"]["agentCapabilities"]["modes"][0]["id"] == "default"
    auth_resp = router.handle({"id": "a", "method": "authenticate", "params": {}})
    assert auth_resp["result"]["authenticated"] is True


def test_router_session_set_mode_noop_ack() -> None:
    router = ACPStdioRouter(_build_cantrip())
    create_resp = router.handle({"id": "n", "method": "session/new", "params": {}})
    session_id = create_resp["result"]["sessionId"]

    resp = router.handle(
        {
            "id": "m",
            "method": "session/setMode",
            "params": {"sessionId": session_id, "modeId": "default"},
        }
    )
    assert resp["id"] == "m"
    assert resp["result"]["sessionId"] == session_id
    assert resp["result"]["modeId"] == "default"


def test_serve_stdio_once_emits_update_then_prompt_response() -> None:
    req = {
        "id": "2",
        "method": "session/prompt",
        "params": {"prompt": [{"type": "text", "text": "hello"}]},
    }
    inp = StringIO(json.dumps(req) + "\n")
    out = StringIO()
    serve_stdio_once(_build_cantrip(), inp, out)
    lines = [json.loads(ln) for ln in out.getvalue().splitlines() if ln.strip()]
    assert len(lines) >= 4
    updates = [ln for ln in lines if ln.get("method") == "session/update"]
    response = lines[-1]
    assert response["id"] == "2"
    assert response["result"]["stopReason"] == "end_turn"
    assert response["result"]["output"][0]["type"] == "text"

    assert any(
        u["params"]["update"]["sessionUpdate"] == "agent_thought_chunk"
        and u["params"]["update"]["content"]["text"].startswith("progress: steps=")
        for u in updates
    )
    assert any(
        u["params"]["update"]["sessionUpdate"] == "tool_call"
        and u["params"]["update"]["status"] == "in_progress"
        for u in updates
    )
    assert any(
        u["params"]["update"]["sessionUpdate"] == "tool_call_update"
        and u["params"]["update"]["status"] in {"completed", "failed"}
        for u in updates
    )
    assert any(
        u["params"]["update"]["sessionUpdate"] == "agent_message_chunk"
        and u["params"]["update"]["content"]["text"] == "ok"
        for u in updates
    )
    assert any(
        u["params"]["update"]["sessionUpdate"] == "agent_message"
        and u["params"]["update"]["content"]["text"] == "ok"
        for u in updates
    )


def test_router_returns_error_for_unknown_method() -> None:
    router = ACPStdioRouter(_build_cantrip())
    resp = router.handle({"id": "x", "method": "unknown.method"})
    assert resp["id"] == "x"
    assert resp["error"]["code"] == "method_not_found"


def test_serve_stdio_once_reads_and_writes_single_json_message() -> None:
    inp = StringIO(json.dumps({"id": "1", "method": "session.create"}) + "\n")
    out = StringIO()
    serve_stdio_once(_build_cantrip(), inp, out)
    payload = json.loads(out.getvalue().strip())
    assert payload["id"] == "1"
    assert "session_id" in payload["result"]


def test_router_session_exists_and_close() -> None:
    router = ACPStdioRouter(_build_cantrip())
    create_resp = router.handle({"id": "1", "method": "session.create"})
    session_id = create_resp["result"]["session_id"]

    exists_resp = router.handle(
        {"id": "2", "method": "session.exists", "params": {"session_id": session_id}}
    )
    assert exists_resp["result"]["exists"] is True

    close_resp = router.handle(
        {"id": "3", "method": "session.close", "params": {"session_id": session_id}}
    )
    assert close_resp["result"]["closed"] is True

    exists_after = router.handle(
        {"id": "4", "method": "session.exists", "params": {"session_id": session_id}}
    )
    assert exists_after["result"]["exists"] is False


def test_router_session_cancel_requests_cancellation_without_closing() -> None:
    router = ACPStdioRouter(_build_cantrip())
    create_resp = router.handle({"id": "1", "method": "session/new"})
    session_id = create_resp["result"]["sessionId"]

    cancel_resp = router.handle(
        {"id": "2", "method": "session/cancel", "params": {"sessionId": session_id}}
    )
    exists_resp = router.handle(
        {"id": "3", "method": "session/exists", "params": {"sessionId": session_id}}
    )

    assert cancel_resp["result"]["cancelled"] is True
    assert cancel_resp["result"]["sessionId"] == session_id
    assert exists_resp["result"]["exists"] is True


def test_serve_stdio_processes_multiple_lines_until_eof() -> None:
    create = {"id": "1", "method": "session.create"}
    # Second request uses an unknown session id, but loop behavior is what we assert.
    cast = {
        "id": "2",
        "method": "cast",
        "params": {"session_id": "missing", "intent": "x"},
    }
    inp = StringIO(json.dumps(create) + "\n" + json.dumps(cast) + "\n")
    out = StringIO()
    serve_stdio(_build_cantrip(), inp, out)
    lines = [ln for ln in out.getvalue().splitlines() if ln.strip()]
    assert len(lines) == 2
    p1 = json.loads(lines[0])
    p2 = json.loads(lines[1])
    assert p1["id"] == "1"
    assert p2["id"] == "2"
    assert "error" in p2


def test_serve_stdio_once_returns_parse_error_for_invalid_json() -> None:
    inp = StringIO("{invalid-json}\n")
    out = StringIO()
    serve_stdio_once(_build_cantrip(), inp, out)
    payload = json.loads(out.getvalue().strip())
    assert payload["id"] is None
    assert payload["error"]["code"] == "parse_error"


def test_router_golden_wire_and_session_prompt_continuity() -> None:
    crystal = FakeCrystal(
        {
            "record_inputs": True,
            "responses": [
                {"tool_calls": [{"gate": "done", "args": {"answer": "one"}}]},
                {"tool_calls": [{"gate": "done", "args": {"answer": "two"}}]},
            ],
        }
    )
    cantrip = Cantrip(
        crystal=crystal, circle=Circle(gates=["done"], wards=[{"max_turns": 3}])
    )
    router = ACPStdioRouter(cantrip)

    init_req = {
        "id": "i1",
        "method": "initialize",
        "params": {"protocolVersion": 1},
    }
    init_resp = router.handle(init_req)
    assert init_resp["id"] == "i1"
    assert init_resp["result"]["capabilities"]["session/prompt"] is True

    new_req = {"id": "n1", "method": "session/new", "params": {}}
    new_resp = router.handle(new_req)
    sid = new_resp["result"]["sessionId"]

    p1_req = {
        "id": "p1",
        "method": "session/prompt",
        "params": {"sessionId": sid, "prompt": [{"type": "text", "text": "first"}]},
    }
    p1_resp = router.handle(p1_req)
    p1_updates = router.notifications_for(p1_req, p1_resp)
    assert [u["params"]["update"]["sessionUpdate"] for u in p1_updates] == [
        "agent_message_chunk",
        "agent_message",
    ]

    p2_req = {
        "id": "p2",
        "method": "session/prompt",
        "params": {"sessionId": sid, "prompt": [{"type": "text", "text": "second"}]},
    }
    p2_resp = router.handle(p2_req)
    p2_updates = router.notifications_for(p2_req, p2_resp)
    assert [u["params"]["update"]["sessionUpdate"] for u in p2_updates] == [
        "agent_message_chunk",
        "agent_message",
    ]

    second_messages = crystal.invocations[1]["messages"]
    user_messages = [m["content"] for m in second_messages if m["role"] == "user"]
    assert any("User: first" in m for m in user_messages)
    assert any("User: second" in m for m in user_messages)


def test_serve_stdio_golden_wire_continuity_across_multiple_requests(
    monkeypatch,
) -> None:
    crystal = FakeCrystal(
        {
            "record_inputs": True,
            "responses": [
                {"tool_calls": [{"gate": "done", "args": {"answer": "one"}}]},
                {"tool_calls": [{"gate": "done", "args": {"answer": "two"}}]},
            ],
        }
    )
    cantrip = Cantrip(
        crystal=crystal, circle=Circle(gates=["done"], wards=[{"max_turns": 3}])
    )
    sid = "00000000-0000-0000-0000-000000000111"
    monkeypatch.setattr(acp_server_mod.uuid, "uuid4", lambda: sid)
    reqs = [
        {"id": "i1", "method": "initialize", "params": {"protocolVersion": 1}},
        {"id": "n1", "method": "session/new", "params": {}},
        {
            "id": "p1",
            "method": "session/prompt",
            "params": {
                "sessionId": sid,
                "prompt": [{"type": "text", "text": "first"}],
            },
        },
        {
            "id": "p2",
            "method": "session/prompt",
            "params": {
                "sessionId": sid,
                "prompt": [{"type": "text", "text": "second"}],
            },
        },
    ]
    inp = StringIO("\n".join(json.dumps(r) for r in reqs) + "\n")
    out = StringIO()
    serve_stdio(cantrip, inp, out)
    lines = [json.loads(ln) for ln in out.getvalue().splitlines() if ln.strip()]
    assert lines[1]["result"]["sessionId"] == sid
    final_responses = [ln for ln in lines if ln.get("id") in {"p1", "p2"}]
    assert len(final_responses) == 2
    assert final_responses[0]["result"]["output"][0]["text"] == "one"
    assert final_responses[1]["result"]["output"][0]["text"] == "two"

    second_messages = crystal.invocations[1]["messages"]
    user_messages = [m["content"] for m in second_messages if m["role"] == "user"]
    assert any("User: first" in m for m in user_messages)
    assert any("User: second" in m for m in user_messages)


def test_router_session_prompt_uses_fallback_text_when_cast_result_is_none() -> None:
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
    router = ACPStdioRouter(cantrip)
    sid = router.handle({"id": "n1", "method": "session/new"})["result"]["sessionId"]
    req = {
        "id": "p1",
        "method": "session/prompt",
        "params": {"sessionId": sid, "prompt": [{"type": "text", "text": "hi"}]},
    }

    resp = router.handle(req)
    updates = router.notifications_for(req, resp)

    assert (
        resp["result"]["output"][0]["text"]
        == "No final answer produced. Last error: gate not available"
    )
    assert (
        updates[1]["params"]["update"]["content"]["text"]
        == "No final answer produced. Last error: gate not available"
    )
    assert (
        updates[0]["params"]["update"]["content"]["text"]
        == "No final answer produced. Last error: gate not available"
    )


def test_router_session_prompt_uses_max_turn_stop_reason_when_truncated() -> None:
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
    router = ACPStdioRouter(cantrip)
    sid = router.handle({"id": "n1", "method": "session/new"})["result"]["sessionId"]
    req = {
        "id": "p1",
        "method": "session/prompt",
        "params": {"sessionId": sid, "prompt": [{"type": "text", "text": "hi"}]},
    }

    resp = router.handle(req)

    assert resp["result"]["stopReason"] == "max_turn_requests"
    assert resp["result"]["output"][0]["text"].startswith(
        "No final answer produced before max_turns."
    )
    assert (
        "Last error: missing required argument: answer"
        in resp["result"]["output"][0]["text"]
    )
    assert resp["result"]["_meta"]["error"]["type"] == "non_terminal_outcome"
    assert resp["result"]["_meta"]["error"]["reason"] == "max_turn_requests"


def test_serve_stdio_once_ignores_non_request_jsonrpc_frames() -> None:
    inp = StringIO(
        json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -1}}) + "\n"
    )
    out = StringIO()
    serve_stdio_once(_build_cantrip(), inp, out)
    assert out.getvalue() == ""


def test_serve_stdio_ignores_non_request_frames_and_processes_next_request() -> None:
    lines = [
        {"jsonrpc": "2.0", "id": "r1", "result": {"ok": True}},
        {"id": "i1", "method": "session.create"},
    ]
    inp = StringIO("\n".join(json.dumps(x) for x in lines) + "\n")
    out = StringIO()
    serve_stdio(_build_cantrip(), inp, out)
    payloads = [json.loads(ln) for ln in out.getvalue().splitlines() if ln.strip()]
    assert len(payloads) == 1
    assert payloads[0]["id"] == "i1"
    assert "result" in payloads[0]


def test_router_session_prompt_returns_text_payload_when_cast_raises(
    monkeypatch,
) -> None:
    router = ACPStdioRouter(_build_cantrip())

    def _raise(*, session_id: str, intent: str, event_sink=None):  # noqa: ARG001
        raise TimeoutError("provider timed out")

    monkeypatch.setattr(router.server, "cast", _raise)
    resp = router.handle(
        {
            "id": "p1",
            "method": "session/prompt",
            "params": {"prompt": [{"type": "text", "text": "hello"}]},
        }
    )

    assert "result" in resp
    assert resp["result"]["stopReason"] == "end_turn"
    assert resp["result"]["output"][0]["text"] == "Error: provider timed out"
    assert resp["result"]["_meta"]["error"]["type"] == "internal_error"
