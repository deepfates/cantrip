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


def test_router_initialize_and_authenticate() -> None:
    router = ACPStdioRouter(_build_cantrip())
    init_resp = router.handle(
        {"id": "i", "method": "initialize", "params": {"protocolVersion": 1}}
    )
    assert init_resp["id"] == "i"
    assert init_resp["result"]["protocolVersion"] == 1
    assert init_resp["result"]["agentInfo"]["name"] == "cantrip-py"
    assert init_resp["result"]["capabilities"]["session/prompt"] is True
    auth_resp = router.handle({"id": "a", "method": "authenticate", "params": {}})
    assert auth_resp["result"]["authenticated"] is True


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
    assert len(lines) == 3
    assert lines[0]["method"] == "session/update"
    assert set(lines[0]["params"]["update"].keys()) == {"sessionUpdate", "content"}
    assert lines[0]["params"]["update"]["content"]["type"] == "text"
    assert set(lines[0]["params"]["update"]["content"].keys()) == {"type", "text"}
    assert lines[0]["params"]["update"]["sessionUpdate"] == "agent_message_chunk"
    assert lines[0]["params"]["update"]["content"]["text"].startswith("progress:")
    assert lines[0]["jsonrpc"] == "2.0"
    assert lines[1]["method"] == "session/update"
    assert set(lines[1]["params"]["update"].keys()) == {"sessionUpdate", "content"}
    assert lines[1]["params"]["update"]["sessionUpdate"] == "agent_message"
    assert lines[2]["id"] == "2"
    assert lines[2]["result"]["stopReason"] == "end_turn"
    assert lines[2]["result"]["output"][0]["type"] == "text"


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
    assert updates[0]["params"]["update"]["content"]["text"].startswith("progress:")


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
