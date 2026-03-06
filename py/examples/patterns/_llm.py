"""Shared LLM resolution for grimoire examples.

mode="scripted" → FakeLLM with provided responses (CI-safe, deterministic).
mode=None       → load .env, build real OpenAICompatLLM, raise if keys missing.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from cantrip import FakeLLM, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

_DOTENV = str(Path(__file__).resolve().parents[2] / ".env")


def resolve_llm(
    mode: str | None = None,
    scripted_responses: list[dict[str, Any]] | None = None,
    timeout_s: float | None = None,
) -> LLM:
    if mode == "scripted":
        return FakeLLM({"responses": scripted_responses or []})
    load_dotenv_if_present(_DOTENV)
    model = os.environ.get("OPENAI_MODEL") or os.environ.get("CANTRIP_OPENAI_MODEL")
    base_url = os.environ.get(
        "OPENAI_BASE_URL",
        os.environ.get("CANTRIP_OPENAI_BASE_URL", "https://api.openai.com/v1"),
    )
    api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get("CANTRIP_OPENAI_API_KEY")
    if not model:
        raise RuntimeError(
            "Missing OPENAI_MODEL (or CANTRIP_OPENAI_MODEL). Set it in .env or environment."
        )
    if not api_key:
        raise RuntimeError(
            "Missing OPENAI_API_KEY (or CANTRIP_OPENAI_API_KEY). Set it in .env or environment."
        )
    env_timeout = os.environ.get("CANTRIP_OPENAI_TIMEOUT_S")
    resolved_timeout = timeout_s or (float(env_timeout) if env_timeout else 120.0)
    return OpenAICompatLLM(
        model=model, base_url=base_url, api_key=api_key, timeout_s=resolved_timeout,
    )


def resolve_llm_pair(
    mode: str | None = None,
    *,
    parent_responses: list[dict[str, Any]] | None = None,
    child_responses: list[dict[str, Any]] | None = None,
) -> tuple[LLM, LLM]:
    """Resolve parent + child LLMs. Real mode uses same LLM for both."""
    if mode == "scripted":
        return (
            FakeLLM({"responses": parent_responses or []}),
            FakeLLM({"responses": child_responses or []}),
        )
    llm = resolve_llm(mode)
    return llm, llm
