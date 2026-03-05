from __future__ import annotations

import json
import os
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "tool medium answer"}}]},
    {"code": "done('code medium answer');"},
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
    # Pattern 6: same gates, different medium, different action space.
    active_llm = _resolve_llm(llm)

    tool_cantrip = Cantrip(
        llm=active_llm,
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}], medium="tool"),
        identity=Identity(system_prompt="Use done(answer)."),
    )
    code_cantrip = Cantrip(
        llm=active_llm,
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}], medium="code"),
        identity=Identity(system_prompt="Work in code and end with done(answer).", require_done_tool=True),
    )

    tool_result, tool_thread = tool_cantrip.cast_with_thread(
        "Summarize the trend in one sentence."
    )
    code_result, code_thread = code_cantrip.cast_with_thread(
        "Compute a summary and return it through done()."
    )

    return {
        "pattern": 6,
        "tool_result": tool_result,
        "code_result": code_result,
        "tool_surface": [t["name"] for t in tool_cantrip._make_tools(tool_cantrip.circle)],
        "code_surface": [t["name"] for t in code_cantrip._make_tools(code_cantrip.circle)],
        "code_observation_gates": [rec.gate_name for rec in code_thread.turns[0].observation],
        "turn_counts": [len(tool_thread.turns), len(code_thread.turns)],
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
