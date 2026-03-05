from __future__ import annotations

import json
import os
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [
            {
                "gate": "call_entity",
                "args": {
                    "intent": "Analyze the regional trend and return one sentence.",
                    "wards": [{"max_turns": 2}, {"max_turns": 6}],
                    "require_done_tool": False,
                },
            }
        ]
    },
    {"tool_calls": [{"gate": "done", "args": {"answer": "Parent synthesized child output."}}]},
]

CHILD_SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"content": "Draft: trend likely positive."},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Trend is positive with stable costs."}}]},
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
    # Pattern 5: wards carve action space; stricter composition wins.
    parent_llm, using_real = _resolve_llm(llm)
    child_llm: LLM = parent_llm if using_real else FakeLLM({"responses": CHILD_SCRIPTED_RESPONSES})

    spell = Cantrip(
        llm=parent_llm,
        child_llm=child_llm,
        identity=Identity(
            system_prompt="Delegate analysis when needed and end with done(answer).",
            require_done_tool=True,
        ),
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 5}, {"max_depth": 2}],
        ),
    )

    result, parent_thread = spell.cast_with_thread(
        "Summarize regional momentum with one delegated pass."
    )
    child_threads = [t for t in spell.loom.list_threads() if t.id != parent_thread.id]
    child_thread = child_threads[0] if child_threads else None

    return {
        "pattern": 5,
        "result": result,
        "parent_turns": len(parent_thread.turns),
        "child_turns": len(child_thread.turns) if child_thread else 0,
        "child_terminated": bool(child_thread and child_thread.terminated),
        "max_turns_min_wins": bool(child_thread and len(child_thread.turns) <= 2),
        "require_done_or": bool(child_thread and len(child_thread.turns) == 2),
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
