from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from cantrip import FakeLLM, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "content": (
            "Revenue rose 14% quarter-over-quarter while support costs stayed flat."
        )
    }
]


def _resolve_llm(mode: str | None = None) -> LLM:
    """Resolve the LLM to use.

    mode="scripted" -> FakeLLM with deterministic responses (CI).
    mode=None       -> load .env, build real LLM, raise if keys missing.
    """
    if mode == "scripted":
        return FakeLLM({"responses": SCRIPTED_RESPONSES})
    # Load .env from repo root (py/.env)
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
    # Pattern 1: a plain LLM query. No circle, no loop, no state.
    active_llm = _resolve_llm(mode)
    messages = [
        {
            "role": "user",
            "content": "Summarize this trend: Revenue up 14%, churn down 2 points.",
        }
    ]
    response = active_llm.query(messages=messages, tools=[], tool_choice=None)
    return {
        "pattern": 1,
        "result": response.content,
        "message_count": len(messages),
        "tool_count": 0,
        "stateless": True,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
