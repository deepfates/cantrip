from __future__ import annotations

import json
import os
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-1"}}]},
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-2"}}]},
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-3"}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Folded and finished."}}]},
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
        return FakeLLM({"responses": SCRIPTED_RESPONSES, "record_inputs": True})


def run(llm: LLM | None = None) -> dict[str, Any]:
    # Pattern 8: long threads trigger folding of old context.
    active_llm = _resolve_llm(llm)
    spell = Cantrip(
        llm=active_llm,
        identity=Identity(
            system_prompt="Use echo for intermediate notes, done when complete."
        ),
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 8}]),
        folding={"trigger_after_turns": 2},
    )

    result, thread = spell.cast_with_thread(
        "Review each region and then summarize the full trend."
    )

    folded_seen = False
    identity_preserved = False
    invocations = getattr(active_llm, "invocations", [])
    for call in invocations:
        messages = call.get("messages", [])
        if any(msg.get("content") == "[folded context]" for msg in messages):
            folded_seen = True
        if messages and messages[0].get("role") == "system":
            identity_preserved = True

    return {
        "pattern": 8,
        "result": result,
        "turn_count": len(thread.turns),
        "folded_context_seen": folded_seen,
        "identity_preserved": identity_preserved,
        "loom_turns": len(spell.loom.turns),
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
