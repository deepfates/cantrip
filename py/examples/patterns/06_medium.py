from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.mediums import medium_for
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "tool medium answer"}}]},
    {"code": "done('code medium answer')"},
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
    # Pattern 6: same gates, different medium, different action space.
    active_llm = _resolve_llm(mode)

    tool_cantrip = Cantrip(
        llm=active_llm,
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}], medium="tool"),
        identity=Identity(system_prompt="You have one tool: done(answer). Call done(answer) with your response."),
    )
    code_cantrip = Cantrip(
        llm=active_llm,
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}], medium="code"),
        identity=Identity(
            system_prompt=(
                "You write Python code using the 'code' tool. "
                "Available function: done(answer). Call done('your answer') to finish. "
                "Variables persist across turns. Example: done('56')"
            ),
            require_done_tool=True,
        ),
    )

    tool_result, tool_thread = tool_cantrip.cast_with_thread(
        "What is the capital of France? Call done(answer) with your response."
    )
    code_result, code_thread = code_cantrip.cast_with_thread(
        "Compute 7 * 8 and return the result by calling done() with the answer."
    )

    return {
        "pattern": 6,
        "tool_result": tool_result,
        "code_result": code_result,
        "tool_surface": [t["name"] for t in medium_for("tool").make_tools(tool_cantrip.circle)],
        "code_surface": [t["name"] for t in medium_for("code").make_tools(code_cantrip.circle)],
        "code_observation_gates": [rec.gate_name for rec in code_thread.turns[0].observation],
        "turn_counts": [len(tool_thread.turns), len(code_thread.turns)],
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
