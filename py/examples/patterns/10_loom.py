from __future__ import annotations

import json
import os
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, InMemoryLoomStore, Loom, OpenAICompatLLM
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [{"gate": "done", "args": {"answer": "Thread one complete."}}],
        "usage": {"prompt_tokens": 11, "completion_tokens": 7},
    },
    {
        "tool_calls": [{"gate": "echo", "args": {"text": "not finished"}}],
        "usage": {"prompt_tokens": 5, "completion_tokens": 3},
    },
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
    # Pattern 10: loom inspection is the most useful artifact.
    loom = Loom(store=InMemoryLoomStore())
    spell = Cantrip(
        llm=_resolve_llm(llm),
        identity=Identity(system_prompt="Use tools and terminate with done(answer)."),
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 1}]),
        loom=loom,
    )

    terminated_result, terminated_thread = spell.cast_with_thread(
        "Give the final outcome for region A."
    )
    truncated_result, truncated_thread = spell.cast_with_thread(
        "Start region B analysis but do not finish."
    )
    threads = loom.list_threads()

    return {
        "pattern": 10,
        "results": [terminated_result, truncated_result],
        "thread_count": len(threads),
        "turn_count": len(loom.turns),
        "terminated": terminated_thread.terminated,
        "truncated": truncated_thread.truncated,
        "total_tokens": [
            terminated_thread.cumulative_usage["total_tokens"],
            truncated_thread.cumulative_usage["total_tokens"],
        ],
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
