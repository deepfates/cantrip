"""Pattern 01: LLM Query (A.1)

A plain LLM call. No circle, no loop, no entity.
This is the simplest building block — just an API call and a response.

Spec ref: LLM-1 (the LLM is stateless; each call is independent).
"""
from __future__ import annotations

import json
from typing import Any

from ._llm import resolve_llm

# Scripted response for CI — a realistic summary the LLM might produce.
_SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "content": (
            "Revenue rose 14% quarter-over-quarter while support costs stayed flat."
        )
    }
]


def run(mode: str | None = None) -> dict[str, Any]:
    print("=== Pattern 01: LLM Query ===")
    print("A plain LLM call. No circle, no loop, no entity.\n")

    # Resolve the LLM: real provider or FakeLLM for CI (LLM-1).
    active_llm = resolve_llm(mode, scripted_responses=_SCRIPTED_RESPONSES)

    # One user message, one response — the simplest possible interaction.
    messages = [
        {
            "role": "user",
            "content": "Summarize this trend: Revenue up 14%, churn down 2 points.",
        }
    ]
    print(f'Asking: "{messages[0]["content"]}"')

    response = active_llm.query(messages=messages, tools=[], tool_choice=None)
    print(f"Response: {response.content}")

    # No state was created. The LLM is exactly as it was before the call (LLM-1).
    print("\nNo state was created. The LLM is stateless — each call is independent.")

    return {
        "pattern": 1,
        "result": response.content,
        "message_count": len(messages),
        "tool_count": 0,
        "stateless": True,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
