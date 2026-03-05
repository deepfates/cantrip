from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, Entity, FakeLLM, Identity, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "1) No atmosphere, 2) 1/6 Earth gravity, 3) Formed from giant impact."}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "The giant impact origin is most surprising because it implies the Moon is made of Earth material."}}]},
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
    # Pattern 11: summon once, send repeatedly, state accumulates.
    active_llm = _resolve_llm(mode)
    spell = Cantrip(
        llm=active_llm,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
        identity=Identity(
            system_prompt=(
                "You are a helpful assistant. Answer questions concisely. "
                "You have one tool: done(answer). Always call done(answer) with your response. "
                "Remember context from previous exchanges."
            )
        ),
    )

    entity: Entity = spell.summon()
    first = entity.send("List 3 interesting facts about the Moon. Call done(answer).")
    second = entity.send("Based on your previous answer, which fact is most surprising and why? Call done(answer).")

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
