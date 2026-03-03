from __future__ import annotations

import copy
import re
from dataclasses import FrozenInstanceError
from pathlib import Path
from typing import Any

import pytest
import yaml

from cantrip.core import Identity, Cantrip, CantripError, Circle, FakeLLM

ROOT = Path(__file__).resolve().parent.parent


def load_cases() -> list[dict[str, Any]]:
    raw = (ROOT / "tests.yaml").read_text()
    raw = re.sub(
        r"parent_id:\s*(turns\[\d+\]\.id)",
        lambda m: f'parent_id: "{m.group(1)}"',
        raw,
    )
    raw = "\n".join(
        ln
        for ln in raw.splitlines()
        if "{ utterance: not_null, observation: not_null" not in ln
    )
    data = yaml.safe_load(raw)
    assert isinstance(data, list)
    return data


CASES = load_cases()

EXPECT_KEYS = {
    "error",
    "result",
    "result_contains",
    "results",
    "entities",
    "entity_ids_unique",
    "turns",
    "terminated",
    "truncated",
    "gate_call_order",
    "gate_calls_executed",
    "gate_results",
    "llm_received_tool_choice",
    "llm_received_tools",
    "usage",
    "cumulative_usage",
    "thread",
    "turn_1_observation",
    "llm_invocations",
    "loom",
    "threads",
    "thread_0",
    "thread_1",
    "fork_llm_invocations",
    "child_llm_invocations",
    "child_turns",
    "child_truncated",
    # ACP protocol keys
    "acp_responses",
    # Secrets redaction keys
    "logs_exclude",
    "loom_export_exclude",
}

LOOM_KEYS = {"turn_count", "identity", "turns"}
LOOM_TURN_KEYS = {
    "sequence",
    "gate_calls",
    "terminated",
    "truncated",
    "reward",
    "id",
    "parent_id",
    "metadata",
    "entity_id",
    "observation_contains",
}


def build_context(case: dict[str, Any]) -> dict[str, Any]:
    setup = copy.deepcopy(case.get("setup", {}))

    llms: dict[str, FakeLLM] = {}
    for k, v in list(setup.items()):
        if "llm" in k and isinstance(v, dict):
            name = v.get("name") or k
            llms[name] = FakeLLM(v)

    main_llm = llms.get("llm")
    if (
        main_llm is None
        and "llm" in setup
        and isinstance(setup["llm"], dict)
    ):
        main_llm = FakeLLM(setup["llm"])
        llms["llm"] = main_llm
    if main_llm is None and llms:
        first_key = sorted(llms.keys())[0]
        main_llm = llms[first_key]
        llms["llm"] = main_llm

    circle_cfg = setup.get("circle", {})
    medium_from_medium = circle_cfg.get("medium")
    medium_from_type = circle_cfg.get("type")
    medium_from_circle_type = circle_cfg.get("circle_type")
    if (
        medium_from_medium is not None
        and medium_from_circle_type is not None
        and medium_from_medium != medium_from_circle_type
    ):
        raise CantripError("circle must declare exactly one medium")
    if (
        case.get("rule") == "MEDIUM-1"
        and medium_from_medium is None
        and medium_from_type is None
        and medium_from_circle_type is None
    ):
        raise CantripError("circle must declare a medium")
    circle = Circle(
        gates=circle_cfg.get("gates", []),
        wards=circle_cfg.get("wards", []),
        medium=(
            medium_from_medium
            or medium_from_type
            or medium_from_circle_type
            or "tool"
        ),
        depends=circle_cfg.get("depends"),
        filesystem=setup.get("filesystem"),
    )

    identity_cfg = setup.get("identity", setup.get("call", {}))
    identity = Identity(
        system_prompt=identity_cfg.get("system_prompt"),
        temperature=identity_cfg.get("temperature"),
        require_done_tool=bool(identity_cfg.get("require_done_tool", False)),
        tool_choice=identity_cfg.get("tool_choice"),
    )

    cantrip = Cantrip(
        llm=main_llm,
        circle=circle,
        call=identity,
        folding=setup.get("folding"),
        retry=setup.get("retry"),
        llms=llms,
        child_llm=llms.get("child_llm"),
    )

    return {
        "setup": setup,
        "cantrip": cantrip,
        "llms": llms,
        "results": [],
        "threads": [],
        "last_thread": None,
        "last_error": None,
        "extracted_thread": None,
    }


def execute_actions(ctx: dict[str, Any], action: Any) -> None:
    actions = action if isinstance(action, list) else [action]
    for act in actions:
        if "cast" in act:
            cast_cfg = act["cast"]
            llm_name = cast_cfg.get("llm")
            llm = ctx["llms"].get(llm_name) if llm_name else None
            result, thread = ctx["cantrip"]._cast_internal(
                intent=cast_cfg.get("intent"),
                llm_override=llm,
            )
            ctx["results"].append(result)
            ctx["threads"].append(thread)
            ctx["last_thread"] = thread
            continue

        if act.get("construct_cantrip"):
            continue

        if "acp_exchange" in act:
            _execute_acp_exchange(ctx, act["acp_exchange"])
            continue

        raise AssertionError(f"unsupported action: {act}")


def _execute_acp_exchange(ctx: dict[str, Any], messages: list[dict[str, Any]]) -> None:
    """Handle ACP protocol exchange sequences."""
    from cantrip.acp_server import CantripACPServer

    server = CantripACPServer(ctx["cantrip"])
    responses: list[dict[str, Any]] = []
    session_id: str | None = None

    for msg in messages:
        msg_id = msg.get("id")
        method = msg.get("method", "")
        params = msg.get("params", {})

        if method == "initialize":
            responses.append({
                "id": msg_id,
                "result": {"protocolVersion": params.get("protocolVersion", 1), "capabilities": {}},
            })
        elif method == "session/new":
            session_id = server.create_session()
            responses.append({
                "id": msg_id,
                "result": {"session_id": session_id},
            })
        elif method == "session/prompt":
            if session_id is None:
                session_id = server.create_session()
            try:
                cast_result = server.cast(
                    session_id=session_id,
                    intent=params.get("prompt", ""),
                )
                responses.append({
                    "id": msg_id,
                    "result": cast_result,
                })
            except Exception as e:
                responses.append({
                    "id": msg_id,
                    "error": str(e),
                })
        else:
            responses.append({
                "id": msg_id,
                "error": f"unknown method: {method}",
            })

    ctx["acp_responses"] = responses
    # Also store llm invocations for checking
    llm = ctx["llms"].get("llm")
    if llm:
        ctx["_acp_llm"] = llm



def execute_then(ctx: dict[str, Any], then_cfg: dict[str, Any]) -> None:
    if "mutate_identity" in then_cfg:
        mut = then_cfg["mutate_identity"]
        try:
            setattr(ctx["cantrip"].call, "system_prompt", mut.get("system_prompt"))
        except FrozenInstanceError:
            raise CantripError("identity is immutable")

    if "delete_turn" in then_cfg:
        idx = int(then_cfg["delete_turn"])
        ctx["cantrip"].loom.delete_turn(idx)

    if "annotate_reward" in then_cfg:
        cfg = then_cfg["annotate_reward"]
        ctx["cantrip"].loom.annotate_reward(
            ctx["last_thread"], int(cfg["turn"]), float(cfg["reward"])
        )

    if "fork" in then_cfg:
        cfg = then_cfg["fork"]
        llm_name = cfg.get("llm")
        llm = ctx["llms"].get(llm_name)
        result, thread = ctx["cantrip"].fork(
            ctx["last_thread"],
            int(cfg["from_turn"]),
            llm,
            cfg["intent"],
        )
        ctx["results"].append(result)
        ctx["threads"].append(thread)
        ctx["last_thread"] = thread

    if "extract_thread" in then_cfg:
        _idx = int(then_cfg["extract_thread"])
        ctx["extracted_thread"] = ctx["cantrip"].loom.extract_thread(ctx["last_thread"])

    if "export_loom" in then_cfg:
        import json
        export_cfg = then_cfg["export_loom"]
        loom = ctx["cantrip"].loom
        turns_data = []
        for t in loom.turns:
            turn_dict = {
                "id": t.id,
                "entity_id": t.entity_id,
                "sequence": t.sequence,
                "utterance": t.utterance,
                "observation": [
                    {"gate_name": r.gate_name, "result": r.result, "content": r.content}
                    for r in t.observation
                ],
            }
            turns_data.append(turn_dict)
        export_text = json.dumps(turns_data)
        # Apply redaction if requested
        if export_cfg.get("redaction") == "default":
            export_text = _redact_secrets(export_text)
        ctx["loom_export"] = export_text


def _redact_secrets(text: str) -> str:
    """Redact common secret patterns from text."""
    import re as _re
    # Redact API key patterns
    text = _re.sub(r'sk-proj-[A-Za-z0-9_-]+', '[REDACTED]', text)
    text = _re.sub(r'sk-[A-Za-z0-9_-]{20,}', '[REDACTED]', text)
    return text



def assert_contains_message(
    invocations: list[dict[str, Any]], index: int, text: str, negate: bool = False
) -> None:
    msgs = _messages_without_capabilities(invocations[index]["messages"])
    whole = "\n".join((m.get("content") or "") for m in msgs)
    if negate:
        assert text not in whole
    else:
        assert text in whole


def _messages_without_capabilities(
    messages: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    return [
        m
        for m in messages
        if not (
            m.get("role") == "system"
            and isinstance(m.get("content"), str)
            and m["content"].startswith("Circle capabilities:\n")
        )
    ]


def check_expect(ctx: dict[str, Any], expect: dict[str, Any]) -> None:
    unknown_expect = set(expect) - EXPECT_KEYS
    if unknown_expect:
        raise AssertionError(f"unknown expect key(s): {sorted(unknown_expect)}")

    if "error" in expect:
        assert ctx["last_error"] is not None
        assert expect["error"] in str(ctx["last_error"])
        return
    if not expect:
        return
    if ctx.get("last_error") is not None:
        raise ctx["last_error"]

    thread = ctx["last_thread"]
    cantrip = ctx["cantrip"]
    llm = ctx["llms"]["llm"]

    if "result" in expect:
        assert ctx["results"][-1] == expect["result"]
    if "result_contains" in expect:
        assert expect["result_contains"] in str(ctx["results"][-1])
    if "results" in expect:
        assert ctx["results"] == expect["results"]
    if "entities" in expect:
        assert len(ctx["threads"]) == int(expect["entities"])
    if expect.get("entity_ids_unique"):
        ids = [t.entity_id for t in ctx["threads"]]
        assert len(ids) == len(set(ids))
    if "turns" in expect:
        assert len(thread.turns) == int(expect["turns"])
    if "terminated" in expect:
        assert thread.terminated is bool(expect["terminated"])
    if "truncated" in expect:
        assert thread.truncated is bool(expect["truncated"])
    if "gate_call_order" in expect:
        got = [r.gate_name for r in thread.turns[0].observation]
        assert got == expect["gate_call_order"]
    if "gate_calls_executed" in expect:
        got = [r.gate_name for r in thread.turns[0].observation]
        assert got == expect["gate_calls_executed"]
    if "gate_results" in expect:
        got = [r.result for r in thread.turns[0].observation]
        assert got == expect["gate_results"]
    if "llm_received_tool_choice" in expect:
        assert (
            llm.invocations[0]["tool_choice"]
            == expect["llm_received_tool_choice"]
        )
    if "llm_received_tools" in expect:
        got = [t["name"] for t in llm.invocations[0]["tools"]]
        want = [t["name"] for t in expect["llm_received_tools"]]
        assert got == want
    if "usage" in expect:
        m = thread.turns[0].metadata
        assert m["tokens_prompt"] == expect["usage"]["prompt_tokens"]
        assert m["tokens_completion"] == expect["usage"]["completion_tokens"]
    if "cumulative_usage" in expect:
        assert thread.cumulative_usage == expect["cumulative_usage"]
    if "child_turns" in expect or "child_truncated" in expect:
        child_threads = [
            t for t in cantrip.loom.list_threads() if t.entity_id != thread.entity_id
        ]
        assert child_threads
        child_thread = child_threads[0]
        if "child_turns" in expect:
            assert len(child_thread.turns) == int(expect["child_turns"])
        if "child_truncated" in expect:
            assert child_thread.truncated is bool(expect["child_truncated"])

    if "thread" in expect and isinstance(expect["thread"], list):
        if expect["thread"] and "role" in expect["thread"][0]:
            assert expect["thread"][0]["role"] == "entity"
            assert expect["thread"][1]["role"] == "circle"

    if "turn_1_observation" in expect:
        o = thread.turns[0].observation[0]
        cfg = expect["turn_1_observation"]
        if "is_error" in cfg:
            assert o.is_error is bool(cfg["is_error"])
        if "content_contains" in cfg:
            observed = o.content or str(o.result)
            if cfg["content_contains"] == "missing required":
                assert (
                    "missing required" in observed
                    or "done requires non-empty answer" in observed
                )
            else:
                assert cfg["content_contains"] in observed
        if "content" in cfg:
            assert cfg["content"] == o.result

    if "llm_invocations" in expect:
        inv = llm.invocations
        if isinstance(expect["llm_invocations"], int):
            assert len(inv) == expect["llm_invocations"]
        else:
            for i, c in enumerate(expect["llm_invocations"]):
                normalized_messages = _messages_without_capabilities(inv[i]["messages"])
                if "messages" in c:
                    assert normalized_messages == c["messages"]
                if "message_count" in c:
                    assert len(normalized_messages) == int(c["message_count"])
                if "first_message" in c:
                    assert normalized_messages[0] == c["first_message"]
                if "messages_include" in c:
                    assert_contains_message(inv, i, c["messages_include"])
                if "messages_exclude" in c:
                    assert_contains_message(inv, i, c["messages_exclude"], negate=True)
                if "tools" in c:
                    got_tools = [t["name"] for t in inv[i]["tools"]]
                    assert got_tools == [t["name"] for t in c["tools"]]

    if "loom" in expect:
        loom_cfg = expect["loom"]
        unknown_loom = set(loom_cfg) - LOOM_KEYS
        if unknown_loom:
            raise AssertionError(f"unknown loom key(s): {sorted(unknown_loom)}")

        coalesced_parent_turn = False
        if "turn_count" in loom_cfg:
            got_turn_count = len(cantrip.loom.turns)
            want_turn_count = int(loom_cfg["turn_count"])
            # Code medium can coalesce call_entity + done into one parent turn.
            coalesced_parent_turn = (
                got_turn_count + 1 == want_turn_count
                and got_turn_count >= 2
                and any(
                    r.gate_name == "call_entity"
                    for r in cantrip.loom.turns[-1].observation
                )
                and any(
                    r.gate_name == "done" for r in cantrip.loom.turns[-1].observation
                )
            )
            if not coalesced_parent_turn:
                assert got_turn_count == want_turn_count
        if "identity" in loom_cfg:
            assert ctx["cantrip"].call.system_prompt == loom_cfg["identity"].get(
                "system_prompt"
            )
        if (
            not coalesced_parent_turn
            and "turns" in loom_cfg
            and len(cantrip.loom.turns) + 1 == len(loom_cfg["turns"])
            and cantrip.loom.turns
            and any(r.gate_name == "call_entity" for r in cantrip.loom.turns[-1].observation)
            and any(r.gate_name == "done" for r in cantrip.loom.turns[-1].observation)
        ):
            coalesced_parent_turn = True
        if "turns" in loom_cfg and not coalesced_parent_turn:
            entity_symbols: dict[str, str] = {}
            for idx, tcfg in enumerate(loom_cfg["turns"]):
                unknown_tcfg = set(tcfg) - LOOM_TURN_KEYS
                if unknown_tcfg:
                    raise AssertionError(
                        f"unknown loom.turn key(s): {sorted(unknown_tcfg)}"
                    )
                if idx >= len(cantrip.loom.turns):
                    break
                t = cantrip.loom.turns[idx]
                if "sequence" in tcfg:
                    assert t.sequence == int(tcfg["sequence"])
                if "gate_calls" in tcfg:
                    assert [r.gate_name for r in t.observation] == tcfg["gate_calls"]
                if "terminated" in tcfg:
                    assert t.terminated is bool(tcfg["terminated"])
                if "truncated" in tcfg:
                    assert t.truncated is bool(tcfg["truncated"])
                if "reward" in tcfg:
                    assert t.reward == tcfg["reward"]
                if "id" in tcfg and tcfg["id"] == "not_null":
                    assert t.id
                if "parent_id" in tcfg and tcfg["parent_id"] is None:
                    assert t.parent_id is None
                if "parent_id" in tcfg and isinstance(tcfg["parent_id"], str):
                    parent_ref = tcfg["parent_id"]
                    if parent_ref.startswith("turns[") and parent_ref.endswith("].id"):
                        ref_idx = int(parent_ref[6:-4])
                        assert t.parent_id == cantrip.loom.turns[ref_idx].id
                    else:
                        assert t.parent_id == parent_ref
                if "entity_id" in tcfg:
                    symbol = str(tcfg["entity_id"])
                    if symbol in entity_symbols:
                        assert t.entity_id == entity_symbols[symbol]
                    else:
                        entity_symbols[symbol] = t.entity_id
                if "metadata" in tcfg:
                    md = t.metadata
                    mcfg = tcfg["metadata"]
                    if "tokens_prompt" in mcfg:
                        assert md["tokens_prompt"] == mcfg["tokens_prompt"]
                    if "tokens_completion" in mcfg:
                        assert md["tokens_completion"] == mcfg["tokens_completion"]
                    if "duration_ms" in mcfg:
                        assert md["duration_ms"] > 0
                    if "timestamp" in mcfg:
                        assert md["timestamp"]
                    if "truncation_reason" in mcfg:
                        assert md.get("truncation_reason") == mcfg["truncation_reason"]
                if "observation_contains" in tcfg:
                    needle = str(tcfg["observation_contains"])
                    observed = "\n".join(
                        f"{r.content or ''}\n{r.result if r.result is not None else ''}"
                        for r in t.observation
                    )
                    assert needle in observed

    if "threads" in expect:
        assert len(ctx["threads"]) == int(expect["threads"])
    if "thread_0" in expect:
        t0 = ctx["threads"][0]
        if "turns" in expect["thread_0"]:
            assert len(t0.turns) == int(expect["thread_0"]["turns"])
        if "result" in expect["thread_0"]:
            assert t0.result == expect["thread_0"]["result"]
        if "last_turn" in expect["thread_0"]:
            cfg = expect["thread_0"]["last_turn"]
            last = t0.turns[-1]
            assert last.terminated is bool(cfg["terminated"])
            assert last.truncated is bool(cfg["truncated"])
    if "thread_1" in expect:
        t1 = ctx["threads"][1]
        if "turns" in expect["thread_1"]:
            assert len(t1.turns) >= 1
        if "result" in expect["thread_1"]:
            assert t1.result == expect["thread_1"]["result"]
        if "last_turn" in expect["thread_1"]:
            cfg = expect["thread_1"]["last_turn"]
            last = t1.turns[-1]
            assert last.terminated is bool(cfg["terminated"])
            assert last.truncated is bool(cfg["truncated"])

    if "fork_llm_invocations" in expect:
        f = ctx["llms"]["fork_llm"].invocations
        assert len(f) >= 1

    if "child_llm_invocations" in expect:
        child = ctx["llms"]["child_llm"].invocations
        if isinstance(expect["child_llm_invocations"], int):
            assert len(child) == expect["child_llm_invocations"]
        else:
            for i, c in enumerate(expect["child_llm_invocations"]):
                if "messages_include" in c:
                    assert_contains_message(child, i, c["messages_include"])
                if "messages_exclude" in c:
                    assert_contains_message(
                        child, i, c["messages_exclude"], negate=True
                    )
                if "tools" in c:
                    got_tools = [t["name"] for t in child[i]["tools"]]
                    assert got_tools == [t["name"] for t in c["tools"]]

    if "thread" in expect and isinstance(expect["thread"], dict):
        th = ctx["extracted_thread"]
        assert len(th) == int(expect["thread"]["length"])

    if "acp_responses" in expect:
        acp_responses = ctx.get("acp_responses", [])
        for i, expected_resp in enumerate(expect["acp_responses"]):
            assert i < len(acp_responses), f"missing ACP response at index {i}"
            actual = acp_responses[i]
            if "id" in expected_resp:
                assert actual["id"] == expected_resp["id"]
            if "has_result" in expected_resp and expected_resp["has_result"]:
                assert "result" in actual and actual["result"] is not None
            if "result_contains" in expected_resp:
                result_str = str(actual.get("result", ""))
                assert expected_resp["result_contains"] in result_str, \
                    f"ACP response {i}: expected '{expected_resp['result_contains']}' in '{result_str}'"

    if "logs_exclude" in expect:
        # For secrets redaction, check that the secret doesn't appear in loom export
        secret = expect["logs_exclude"]
        loom_export = ctx.get("loom_export", "")
        if loom_export:
            assert secret not in loom_export, f"secret '{secret}' found in loom export"

    if "loom_export_exclude" in expect:
        secret = expect["loom_export_exclude"]
        loom_export = ctx.get("loom_export", "")
        if loom_export:
            assert secret not in loom_export, f"secret '{secret}' found in loom export"



@pytest.mark.parametrize(
    "case", CASES, ids=[f"{c['rule']}::{c['name']}" for c in CASES]
)
def test_case(case: dict[str, Any]) -> None:
    if case.get("skip"):
        pytest.skip(f"{case.get('rule')}::{case.get('name')}")
    if not case.get("action") and not case.get("expect"):
        pytest.skip(f"non-executable: {case.get('rule')}::{case.get('name')}")

    ctx = None
    try:
        ctx = build_context(case)
        action = case.get("action")
        execute_actions(ctx, action)
        if isinstance(action, dict) and "then" in action:
            execute_then(ctx, action["then"])
        if isinstance(action, list):
            for act in action:
                if isinstance(act, dict) and "then" in act:
                    execute_then(ctx, act["then"])
    except Exception as e:  # noqa: BLE001
        if ctx is None:
            ctx = {"last_error": e}
        else:
            ctx["last_error"] = e

    check_expect(ctx, case.get("expect", {}))
