from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [
            {
                "gate": "call_entity",
                "args": {
                    "intent": "List 3 facts about solar energy. Call done(answer) with your list.",
                    "wards": [{"max_turns": 2}, {"max_turns": 6}],
                },
            }
        ]
    },
    {"tool_calls": [{"gate": "done", "args": {"answer": "Child found 3 solar energy facts; delegation complete."}}]},
]

CHILD_SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"content": "Let me think about solar energy facts."},
    {"tool_calls": [{"gate": "done", "args": {"answer": "1) Solar is renewable. 2) Panels last 25+ years. 3) Costs dropped 90% since 2010."}}]},
]


def _resolve_llm(mode: str | None = None) -> tuple[LLM, bool]:
    if mode == "scripted":
        return FakeLLM({"responses": SCRIPTED_RESPONSES}), False
    load_dotenv_if_present(str(Path(__file__).resolve().parents[2] / ".env"))
    model = os.environ.get("OPENAI_MODEL") or os.environ.get("CANTRIP_OPENAI_MODEL")
    base_url = os.environ.get("OPENAI_BASE_URL", os.environ.get("CANTRIP_OPENAI_BASE_URL", "https://api.openai.com/v1"))
    api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get("CANTRIP_OPENAI_API_KEY")
    if not model:
        raise RuntimeError("Missing OPENAI_MODEL (or CANTRIP_OPENAI_MODEL). Set it in .env or environment.")
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY (or CANTRIP_OPENAI_API_KEY). Set it in .env or environment.")
    return OpenAICompatLLM(model=model, base_url=base_url, api_key=api_key), True


def run(mode: str | None = None) -> dict[str, Any]:
    # Pattern 5: wards carve action space; stricter composition wins.
    parent_llm, using_real = _resolve_llm(mode)
    child_llm: LLM = parent_llm if using_real else FakeLLM({"responses": CHILD_SCRIPTED_RESPONSES})

    spell = Cantrip(
        llm=parent_llm,
        child_llm=child_llm,
        identity=Identity(
            system_prompt=(
                "You are a delegator. You have two tools:\n"
                "  call_entity(intent=...) — delegate a task to a child\n"
                "  done(answer=...) — finish with your final answer\n"
                "Delegate the user's question to a child, then pass the child's answer to done()."
            ),
            require_done_tool=True,
        ),
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 5}, {"max_depth": 1}],
        ),
    )

    result, parent_thread = spell.cast_with_thread(
        "List 3 facts about renewable energy by delegating to a child entity, then call done(answer)."
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
