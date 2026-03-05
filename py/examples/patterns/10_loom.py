from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, InMemoryLoomStore, Loom, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

# Separate scripted responses for each cast.
TERMINATED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [{"gate": "done", "args": {"answer": "The capital of France is Paris."}}],
        "usage": {"prompt_tokens": 11, "completion_tokens": 7},
    },
]

TRUNCATED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [{"gate": "echo", "args": {"text": "Paris, London, Berlin"}}],
        "usage": {"prompt_tokens": 5, "completion_tokens": 3},
    },
    {
        "tool_calls": [{"gate": "echo", "args": {"text": "Madrid, Rome, Vienna"}}],
        "usage": {"prompt_tokens": 5, "completion_tokens": 3},
    },
    {
        "tool_calls": [{"gate": "echo", "args": {"text": "Warsaw, Prague, Lisbon"}}],
        "usage": {"prompt_tokens": 5, "completion_tokens": 3},
    },
]


def _resolve_llm(mode: str | None = None) -> LLM:
    if mode == "scripted":
        return FakeLLM({"responses": []})  # unused — each cast gets its own FakeLLM
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
    # Pattern 10: loom inspection is the most useful artifact (LOOM-3, LOOM-7).
    loom = Loom(store=InMemoryLoomStore())
    is_scripted = mode == "scripted"

    # Ensure env vars are checked even in real mode (no silent fallback).
    if not is_scripted:
        _resolve_llm(mode)

    # Cast 1: only gate is done → entity MUST terminate.
    terminated_llm = FakeLLM({"responses": TERMINATED_RESPONSES}) if is_scripted else _resolve_llm(mode)
    terminated_spell = Cantrip(
        llm=terminated_llm,
        identity=Identity(
            system_prompt="You have one tool: done(answer). Call it with your response.",
            require_done_tool=True,
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
        loom=loom,
    )
    terminated_result, terminated_thread = terminated_spell.cast_with_thread(
        "What is the capital of France?"
    )

    # Cast 2: echo available, low turn limit → entity truncated before finishing.
    truncated_llm = FakeLLM({"responses": TRUNCATED_RESPONSES}) if is_scripted else _resolve_llm(mode)
    truncated_spell = Cantrip(
        llm=truncated_llm,
        identity=Identity(
            system_prompt=(
                "You have echo(text) and done(answer). "
                "Use echo for every observation. Only call done when you have a complete answer."
            ),
            require_done_tool=True,
        ),
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 3}]),
        loom=loom,
    )
    truncated_result, truncated_thread = truncated_spell.cast_with_thread(
        "List as many European capitals as you can, echoing each one with echo(text)."
    )
    threads = loom.list_threads()

    return {
        "pattern": 10,
        "results": [terminated_result, truncated_result],
        "thread_count": len(threads),
        "turn_count": len(loom.turns),
        "terminated": terminated_thread.terminated,
        "truncated": truncated_thread.truncated,
        "total_tokens": [
            terminated_thread.cumulative_usage["total_tokens"],
            truncated_thread.cumulative_usage["total_tokens"],
        ],
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
