from __future__ import annotations

import json
import os
from typing import Any

from cantrip import FakeLLM, OpenAICompatLLM
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "content": (
            "Revenue rose 14% quarter-over-quarter while support costs stayed flat."
        )
    }
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
    # Pattern 1: a plain LLM query. No circle, no loop, no state.
    active_llm = _resolve_llm(llm)
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
