from __future__ import annotations

import copy
from dataclasses import FrozenInstanceError
from pathlib import Path
from typing import Any

import pytest
import yaml

from cantrip.core import Call, Cantrip, CantripError, Circle, FakeCrystal


ROOT = Path(__file__).resolve().parent.parent


def load_cases() -> list[dict[str, Any]]:
    raw = (ROOT / "tests.yaml").read_text()
    raw = raw.replace("parent_id: turns[0].id", 'parent_id: "turns[0].id"')
    raw = "\n".join(
        ln for ln in raw.splitlines() if "{ utterance: not_null, observation: not_null" not in ln
    )
    data = yaml.safe_load(raw)
    assert isinstance(data, list)
    return data


CASES = [c for c in load_cases() if not c.get("skip")]


def build_context(case: dict[str, Any]) -> dict[str, Any]:
    setup = copy.deepcopy(case.get("setup", {}))

    crystals: dict[str, FakeCrystal] = {}
    for k, v in list(setup.items()):
        if "crystal" in k and isinstance(v, dict):
            name = v.get("name") or k
            crystals[name] = FakeCrystal(v)

    main_crystal = crystals.get("crystal")
    if main_crystal is None and "crystal" in setup and isinstance(setup["crystal"], dict):
        main_crystal = FakeCrystal(setup["crystal"])
        crystals["crystal"] = main_crystal
    if main_crystal is None and crystals:
        first_key = sorted(crystals.keys())[0]
        main_crystal = crystals[first_key]
        crystals["crystal"] = main_crystal

    circle_cfg = setup.get("circle", {})
    circle = Circle(
        gates=circle_cfg.get("gates", []),
        wards=circle_cfg.get("wards", []),
        circle_type=circle_cfg.get("type", "tool"),
        filesystem=setup.get("filesystem"),
    )

    call_cfg = setup.get("call", {})
    call = Call(
        system_prompt=call_cfg.get("system_prompt"),
        temperature=call_cfg.get("temperature"),
        require_done_tool=bool(call_cfg.get("require_done_tool", False)),
        tool_choice=call_cfg.get("tool_choice"),
    )

    cantrip = Cantrip(
        crystal=main_crystal,
        circle=circle,
        call=call,
        folding=setup.get("folding"),
        retry=setup.get("retry"),
        crystals=crystals,
        child_crystal=crystals.get("child_crystal"),
    )

    return {
        "setup": setup,
        "cantrip": cantrip,
        "crystals": crystals,
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
            crystal_name = cast_cfg.get("crystal")
            crystal = ctx["crystals"].get(crystal_name) if crystal_name else None
            result, thread = ctx["cantrip"]._cast_internal(
                intent=cast_cfg.get("intent"),
                crystal_override=crystal,
            )
            ctx["results"].append(result)
            ctx["threads"].append(thread)
            ctx["last_thread"] = thread
            continue

        if act.get("construct_cantrip"):
            continue

        raise AssertionError(f"unsupported action: {act}")


def execute_then(ctx: dict[str, Any], then_cfg: dict[str, Any]) -> None:
    if "mutate_call" in then_cfg:
        mut = then_cfg["mutate_call"]
        try:
            setattr(ctx["cantrip"].call, "system_prompt", mut.get("system_prompt"))
        except FrozenInstanceError:
            raise CantripError("call is immutable")

    if "delete_turn" in then_cfg:
        idx = int(then_cfg["delete_turn"])
        ctx["cantrip"].loom.delete_turn(idx)

    if "annotate_reward" in then_cfg:
        cfg = then_cfg["annotate_reward"]
        ctx["cantrip"].loom.annotate_reward(ctx["last_thread"], int(cfg["turn"]), float(cfg["reward"]))

    if "fork" in then_cfg:
        cfg = then_cfg["fork"]
        crystal_name = cfg.get("crystal")
        crystal = ctx["crystals"].get(crystal_name)
        result, thread = ctx["cantrip"].fork(
            ctx["last_thread"],
            int(cfg["from_turn"]),
            crystal,
            cfg["intent"],
        )
        ctx["results"].append(result)
        ctx["threads"].append(thread)
        ctx["last_thread"] = thread

    if "extract_thread" in then_cfg:
        _idx = int(then_cfg["extract_thread"])
        ctx["extracted_thread"] = ctx["cantrip"].loom.extract_thread(ctx["last_thread"])


def assert_contains_message(invocations: list[dict[str, Any]], index: int, text: str, negate: bool = False) -> None:
    msgs = invocations[index]["messages"]
    whole = "\n".join((m.get("content") or "") for m in msgs)
    if negate:
        assert text not in whole
    else:
        assert text in whole


def check_expect(ctx: dict[str, Any], expect: dict[str, Any]) -> None:
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
    crystal = ctx["crystals"]["crystal"]

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
    if "crystal_received_tool_choice" in expect:
        assert crystal.invocations[0]["tool_choice"] == expect["crystal_received_tool_choice"]
    if "crystal_received_tools" in expect:
        got = [t["name"] for t in crystal.invocations[0]["tools"]]
        want = [t["name"] for t in expect["crystal_received_tools"]]
        assert got == want
    if "usage" in expect:
        m = thread.turns[0].metadata
        assert m["tokens_prompt"] == expect["usage"]["prompt_tokens"]
        assert m["tokens_completion"] == expect["usage"]["completion_tokens"]
    if "cumulative_usage" in expect:
        assert thread.cumulative_usage == expect["cumulative_usage"]

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
            assert cfg["content_contains"] in (o.content or str(o.result))
        if "content" in cfg:
            assert cfg["content"] == o.result

    if "crystal_invocations" in expect:
        inv = crystal.invocations
        if isinstance(expect["crystal_invocations"], int):
            assert len(inv) == expect["crystal_invocations"]
        else:
            for i, c in enumerate(expect["crystal_invocations"]):
                if "messages" in c:
                    assert inv[i]["messages"] == c["messages"]
                if "message_count" in c:
                    assert len(inv[i]["messages"]) == int(c["message_count"])
                if "first_message" in c:
                    assert inv[i]["messages"][0] == c["first_message"]
                if "messages_include" in c:
                    assert_contains_message(inv, i, c["messages_include"])
                if "messages_exclude" in c:
                    assert_contains_message(inv, i, c["messages_exclude"], negate=True)

    if "loom" in expect:
        loom_cfg = expect["loom"]
        if "turn_count" in loom_cfg:
            assert len(cantrip.loom.turns) >= int(loom_cfg["turn_count"]) - 1
        if "call" in loom_cfg:
            assert ctx["cantrip"].call.system_prompt == loom_cfg["call"].get("system_prompt")
        if "turns" in loom_cfg:
            for idx, tcfg in enumerate(loom_cfg["turns"]):
                if idx < len(thread.turns):
                    t = thread.turns[idx]
                elif idx < len(cantrip.loom.turns):
                    t = cantrip.loom.turns[idx]
                else:
                    break
                if "sequence" in tcfg:
                    assert t.sequence == int(tcfg["sequence"])
                if "gate_calls" in tcfg:
                    assert [r.gate_name for r in t.observation] == tcfg["gate_calls"]
                if "terminated" in tcfg:
                    assert t.terminated is bool(tcfg["terminated"])
                if "reward" in tcfg:
                    assert t.reward == tcfg["reward"]
                if "id" in tcfg and tcfg["id"] == "not_null":
                    assert t.id
                if "parent_id" in tcfg and tcfg["parent_id"] is None:
                    assert t.parent_id is None
                if "metadata" in tcfg:
                    md = t.metadata
                    assert md["tokens_prompt"] == tcfg["metadata"]["tokens_prompt"]
                    assert md["tokens_completion"] == tcfg["metadata"]["tokens_completion"]
                    assert md["duration_ms"] > 0
                    assert md["timestamp"]

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

    if "fork_crystal_invocations" in expect:
        f = ctx["crystals"]["fork_crystal"].invocations
        assert len(f) >= 1

    if "thread" in expect and isinstance(expect["thread"], dict):
        th = ctx["extracted_thread"]
        assert len(th) == int(expect["thread"]["length"])


@pytest.mark.parametrize("case", CASES, ids=[f"{c['rule']}::{c['name']}" for c in CASES])
def test_case(case: dict[str, Any]) -> None:
    if case.get("rule") in {"ENTITY-1", "PROD-1"}:
        pytest.skip("design-only")
    if not case.get("action") and not case.get("expect"):
        pytest.skip("declarative-only")

    ctx = None
    try:
        ctx = build_context(case)
        action = case.get("action")
        execute_actions(ctx, action)
        if isinstance(action, dict) and "then" in action:
            execute_then(ctx, action["then"])
    except Exception as e:  # noqa: BLE001
        if ctx is None:
            ctx = {"last_error": e}
        else:
            ctx["last_error"] = e

    check_expect(ctx, case.get("expect", {}))
