from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

# Parent uses code medium: writes Python code that calls call_entity_batch().
# Children inherit code medium, so their responses are also code tool calls.
SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [{
            "gate": "code",
            "args": {
                "code": (
                    "results = call_entity_batch(["
                    '{"intent": "List 3 benefits of exercise"}, '
                    '{"intent": "List 3 benefits of sleep"}'
                    "])\n"
                    "done('combined: ' + str(results))"
                )
            },
        }]
    },
]

CHILD_SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "code", "args": {"code": "done('Exercise: cardiovascular health, mood, strength.')"}}]},
    {"tool_calls": [{"gate": "code", "args": {"code": "done('Sleep: memory consolidation, immune function, recovery.')"}}]},
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
    # Pattern 9: parent delegates via call_entity_batch in code medium (COMP-3).
    parent_llm, using_real = _resolve_llm(mode)
    child_llm: LLM = parent_llm if using_real else FakeLLM({"responses": CHILD_SCRIPTED_RESPONSES})

    spell = Cantrip(
        llm=parent_llm,
        child_llm=child_llm,
        identity=Identity(
            system_prompt=(
                "You are a coordinator. Use the code tool to write Python.\n"
                "Available functions:\n"
                "  call_entity_batch(list_of_dicts) — delegate tasks to children in parallel\n"
                "  done(answer) — finish with your final answer\n"
                "Each dict needs an 'intent' key with a clear description of what the child should do.\n"
                "Children will return string results.\n"
                "Combine their results and call done()."
            ),
            require_done_tool=True,
        ),
        circle=Circle(
            medium="code",
            gates=["done", "call_entity", "call_entity_batch"],
            wards=[{"max_turns": 6}, {"max_depth": 1}],
        ),
        medium_depends={"code": {"timeout_s": 60}},
    )

    result, parent_thread = spell.cast_with_thread(
        "Delegate two tasks: (1) list 3 benefits of exercise, (2) list 3 benefits of sleep. "
        "Use call_entity_batch, then combine the results with done(answer)."
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
