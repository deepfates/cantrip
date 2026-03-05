from __future__ import annotations

import json
import os
from typing import Any

from cantrip import Cantrip, Circle, Entity, FakeLLM, Identity, OpenAICompatLLM
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "Initial anomaly scan complete."}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Follow-up used prior anomaly context."}}]},
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
    # Pattern 11: summon once, send repeatedly, state accumulates.
    active_llm = _resolve_llm(llm)
    spell = Cantrip(
        llm=active_llm,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
        identity=Identity(system_prompt="Track prior answers and return concise updates."),
    )

    entity: Entity = spell.summon()
    first = entity.send("Inspect category A and list anomalies.")
    second = entity.send("Now prioritize the anomalies you already found.")

    invocations = getattr(active_llm, "invocations", [])
    second_prompt = ""
    if len(invocations) >= 2:
        second_prompt = invocations[1]["messages"][2]["content"]

    return {
        "pattern": 11,
        "first": first,
        "second": second,
        "accumulated_turns": len(entity.turns),
        "last_thread_turns": len(entity.last_thread.turns) if entity.last_thread else 0,
        "remembers_prior_turn": "Conversation so far:" in second_prompt,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
