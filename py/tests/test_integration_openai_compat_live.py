from __future__ import annotations

import os

import pytest

from cantrip import Call, Cantrip, Circle
from cantrip.env import load_dotenv_if_present
from cantrip.providers.openai_compat import OpenAICompatCrystal

load_dotenv_if_present()


def _integration_enabled() -> bool:
    return os.getenv("CANTRIP_INTEGRATION_LIVE", "").lower() in {"1", "true", "yes"}


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        pytest.skip(f"missing required env var: {name}")
    return value


@pytest.mark.skipif(
    not _integration_enabled(),
    reason="set CANTRIP_INTEGRATION_LIVE=1 to run live provider tests",
)
def test_live_openai_compat_query_text_roundtrip() -> None:
    model = _required_env("CANTRIP_OPENAI_MODEL")
    base_url = _required_env("CANTRIP_OPENAI_BASE_URL")
    api_key = os.getenv("CANTRIP_OPENAI_API_KEY", "")

    crystal = OpenAICompatCrystal(
        model=model, base_url=base_url, api_key=api_key, timeout_s=90
    )
    response = crystal.query(
        messages=[{"role": "user", "content": "Reply with exactly: cantrip-live-ok"}],
        tools=[],
        tool_choice=None,
    )

    assert response.content is not None
    assert "cantrip-live-ok" in response.content.lower()
    assert response.tool_calls in (None, [])
    assert isinstance(response.usage, dict)
    assert int(response.usage.get("completion_tokens", 0)) > 0


@pytest.mark.skipif(
    not _integration_enabled(),
    reason="set CANTRIP_INTEGRATION_LIVE=1 to run live provider tests",
)
def test_live_cantrip_tool_circle_done_path() -> None:
    model = _required_env("CANTRIP_OPENAI_MODEL")
    base_url = _required_env("CANTRIP_OPENAI_BASE_URL")
    api_key = os.getenv("CANTRIP_OPENAI_API_KEY", "")

    crystal = OpenAICompatCrystal(
        model=model, base_url=base_url, api_key=api_key, timeout_s=90
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}]),
        call=Call(
            system_prompt=(
                "You are a strict test agent. Always finish by calling done with answer='ok'."
            ),
            tool_choice="required",
            require_done_tool=True,
        ),
    )
    result, thread = cantrip.cast_with_thread(intent="Return success now.")
    assert thread.terminated is True
    assert thread.truncated is False
    assert thread.turns
    assert len(thread.turns) <= 4
    assert thread.cumulative_usage["completion_tokens"] > 0
    assert (
        thread.cumulative_usage["total_tokens"]
        >= thread.cumulative_usage["completion_tokens"]
    )

    unavailable_errors = [
        rec
        for t in thread.turns
        for rec in t.observation
        if rec.is_error and rec.content == "gate not available"
    ]
    assert unavailable_errors == []

    done_calls = [
        rec
        for rec in thread.turns[-1].observation
        if rec.gate_name == "done" and not rec.is_error
    ]
    assert done_calls, "expected a successful done gate call on final turn"
    # Some real models may leave answer empty; this test validates protocol/runtime behavior.
    assert result == done_calls[-1].result
