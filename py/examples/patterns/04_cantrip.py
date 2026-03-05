from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "China, India, and the United States are the three largest countries by population."}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "The Pacific, Atlantic, and Indian Oceans are the three largest by area."}}]},
]


def _resolve_llm(mode: str | None = None) -> LLM:
    if mode == "scripted":
        return FakeLLM({"responses": SCRIPTED_RESPONSES})
    load_dotenv_if_present(str(Path(__file__).resolve().parents[2] / ".env"))
    model = os.environ.get("OPENAI_MODEL") or os.environ.get("CANTRIP_OPENAI_MODEL")
    base_url = os.environ.get("OPENAI_BASE_URL", os.environ.get("CANTRIP_OPENAI_BASE_URL", "https://api.openai.com/v1"))
    api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get("CANTRIP_OPENAI_API_KEY")
    if not model:
        raise RuntimeError("Missing OPENAI_MODEL (or CANTRIP_OPENAI_MODEL). Set it in .env or environment.")
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY (or CANTRIP_OPENAI_API_KEY). Set it in .env or environment.")
    return OpenAICompatLLM(model=model, base_url=base_url, api_key=api_key)


def run(mode: str | None = None) -> dict[str, Any]:
    # Pattern 4: llm + identity + circle = cantrip.
    spell = Cantrip(
        llm=_resolve_llm(mode),
        identity=Identity(
            system_prompt=(
                "You are a helpful assistant. Answer questions concisely. "
                "You have one tool: done(answer). Call done(answer) with a one-sentence summary."
            )
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}]),
    )

    result_1, thread_1 = spell.cast_with_thread(
        "What are the three largest countries by population? Use done(answer) with a one-sentence summary."
    )
    result_2, thread_2 = spell.cast_with_thread(
        "What are the three largest oceans by area? Use done(answer) with a one-sentence summary."
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
