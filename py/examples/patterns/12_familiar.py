from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from cantrip import (
    Cantrip,
    Circle,
    Entity,
    FakeLLM,
    Identity,
    Loom,
    OpenAICompatLLM,
    SQLiteLoomStore,
)
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "code": (
            "var a = call_entity({intent: 'Analyze metrics in code', llm: 'child_code', medium: 'code', wards: [{max_turns: 2}]});"
            "var b = call_entity({intent: 'Write narrative summary', llm: 'child_tool', medium: 'tool', wards: [{max_turns: 2}]});"
            "done(a + ' | ' + b);"
        )
    },
    {
        "code": (
            "var a = call_entity({intent: 'Re-check metrics in code', llm: 'child_code', medium: 'code', wards: [{max_turns: 2}]});"
            "var b = call_entity({intent: 'Re-check narrative summary', llm: 'child_tool', medium: 'tool', wards: [{max_turns: 2}]});"
            "done(a + ' | ' + b);"
        )
    },
]

CHILD_CODE_RESPONSES: list[dict[str, Any]] = [
    {"code": "done('code-child: trend computed');"},
    {"code": "done('code-child: trend re-computed');"},
]

CHILD_TOOL_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "tool-child: summary drafted"}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "tool-child: summary refined"}}]},
]


def _resolve_llm(llm: LLM | None) -> tuple[LLM, bool]:
    if llm is not None:
        return llm, True
    try:
        resolved = OpenAICompatLLM(
            model=os.environ["CANTRIP_OPENAI_MODEL"],
            base_url=os.environ["CANTRIP_OPENAI_BASE_URL"],
            api_key=os.getenv("CANTRIP_OPENAI_API_KEY"),
        )
        return resolved, True
    except Exception:
        return FakeLLM({"responses": SCRIPTED_RESPONSES}), False


def run(llm: LLM | None = None) -> dict[str, Any]:
    # Pattern 12: familiar coordinates child cantrips and keeps a persistent loom.
    parent_llm, using_real = _resolve_llm(llm)

    if using_real:
        child_code_llm: LLM = parent_llm
        child_tool_llm: LLM = parent_llm
    else:
        child_code_llm = FakeLLM({"responses": CHILD_CODE_RESPONSES})
        child_tool_llm = FakeLLM({"responses": CHILD_TOOL_RESPONSES})

    loom_path = Path(tempfile.mkdtemp(prefix="cantrip-familiar-")) / "loom.db"
    loom = Loom(store=SQLiteLoomStore(loom_path))

    familiar_spell = Cantrip(
        llm=parent_llm,
        llms={"child_code": child_code_llm, "child_tool": child_tool_llm},
        circle=Circle(
            medium="code",
            gates=["done", "call_entity"],
            wards=[{"max_turns": 6}, {"max_depth": 2}],
        ),
        identity=Identity(
            system_prompt=(
                "You are a coordinator. Delegate to child entities with call_entity and finalize with done(answer)."
            ),
            require_done_tool=True,
        ),
        loom=loom,
    )

    familiar: Entity = familiar_spell.summon()
    first = familiar.send("Analyze each category and produce a report.")
    second = familiar.send("Run a second pass and refine the report.")

    thread_ids = [t.id for t in loom.list_threads()]
    reloaded = Loom(store=SQLiteLoomStore(loom_path))
    persisted_any = bool(thread_ids and reloaded.get_thread(thread_ids[0]) is not None)

    return {
        "pattern": 12,
        "first": first,
        "second": second,
        "loom_threads": len(loom.list_threads()),
        "entity_turns": len(familiar.turns),
        "persisted_loom": persisted_any,
        "child_code_calls": len(getattr(child_code_llm, "invocations", [])),
        "child_tool_calls": len(getattr(child_tool_llm, "invocations", [])),
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
