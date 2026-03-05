from __future__ import annotations

import json
import os
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "Revenue accelerated in enterprise."}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Support costs stabilized while volume grew."}}]},
]


def _resolve_llm(llm: LLM | None) -> LLM:
    if llm is not None:
        return llm
    try:
        return OpenAICompatLLM(
            model=os.environ["CANTRIP_OPENAI_MODEL"],
            base_url=os.environ["CANTRIP_OPENAI_BASE_URL"],
            api_key=os.getenv("CANTRIP_OPENAI_API_KEY"),
        )
    except Exception:
        return FakeLLM({"responses": SCRIPTED_RESPONSES})


def run(llm: LLM | None = None) -> dict[str, Any]:
    # Pattern 4: llm + identity + circle = cantrip.
    spell = Cantrip(
        llm=_resolve_llm(llm),
        identity=Identity(
            system_prompt=(
                "You are an analyst. Use done(answer) with a concise final finding."
            )
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}]),
    )

    result_1, thread_1 = spell.cast_with_thread(
        "Analyze sales by segment and summarize the primary trend."
    )
    result_2, thread_2 = spell.cast_with_thread(
        "Analyze support ticket mix and summarize the operational trend."
    )

    return {
        "pattern": 4,
        "result_1": result_1,
        "result_2": result_2,
        "thread_ids": [thread_1.id, thread_2.id],
        "independent_threads": thread_1.id != thread_2.id,
        "turn_counts": [len(thread_1.turns), len(thread_2.turns)],
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
