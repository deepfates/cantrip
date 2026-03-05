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
                "gate": "call_entity_batch",
                "args": [
                    {"intent": "Analyze revenue signals."},
                    {"intent": "Analyze cost signals."},
                ],
            }
        ]
    },
    {"tool_calls": [{"gate": "done", "args": {"answer": "Parent merged child analyses."}}]},
]

CHILD_SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "Revenue: accelerating."}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Costs: stable."}}]},
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
    # Pattern 9: parent delegates, children run independently.
    parent_llm, using_real = _resolve_llm(llm)
    child_llm: LLM = parent_llm if using_real else FakeLLM({"responses": CHILD_SCRIPTED_RESPONSES})

    spell = Cantrip(
        llm=parent_llm,
        child_llm=child_llm,
        identity=Identity(system_prompt="Delegate by topic, then synthesize with done(answer)."),
        circle=Circle(
            gates=["done", "call_entity", "call_entity_batch"],
            wards=[{"max_turns": 6}, {"max_depth": 1}],
        ),
    )

    result, parent_thread = spell.cast_with_thread(
        "Analyze revenue and costs, then provide one synthesis."
    )
    all_threads = spell.loom.list_threads()
    child_threads = [t for t in all_threads if t.id != parent_thread.id]
    batch_record = parent_thread.turns[0].observation[0] if parent_thread.turns else None

    return {
        "pattern": 9,
        "result": result,
        "parent_turns": len(parent_thread.turns),
        "child_threads": len(child_threads),
        "child_thread_ids": [t.id for t in child_threads],
        "batch_result_count": len(batch_record.result) if batch_record and isinstance(batch_record.result, list) else 0,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
