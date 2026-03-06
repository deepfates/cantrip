from __future__ import annotations

import json

import pytest

from cantrip.errors import CantripError, ProviderError, ProviderTimeout, ProviderTransportError
from cantrip.providers.openai_compat import OpenAICompatLLM


class _Resp:
    def __init__(self, status_code: int, payload: dict):
        self.status_code = status_code
        self._payload = payload
        self.text = json.dumps(payload)

    def json(self):
        return self._payload


def test_openai_compat_normalizes_response(monkeypatch: pytest.MonkeyPatch) -> None:
    def _post(*_args, **_kwargs):
        return _Resp(
            200,
            {
                "choices": [
                    {
                        "message": {
                            "content": "hi",
                            "tool_calls": [
                                {
                                    "id": "tc_1",
                                    "function": {
                                        "name": "done",
                                        "arguments": '{"answer":"ok"}',
                                    },
                                }
                            ],
                        }
                    }
                ],
                "usage": {"prompt_tokens": 11, "completion_tokens": 7},
            },
        )

    monkeypatch.setattr("cantrip.providers.openai_compat.requests.post", _post)
    c = OpenAICompatLLM(
        model="gpt-test", base_url="https://example.com", api_key="x"
    )
    r = c.query(
        messages=[{"role": "user", "content": "x"}],
        tools=[{"name": "done", "parameters": {}}],
        tool_choice="required",
    )

    assert r.content == "hi"
    assert r.tool_calls and r.tool_calls[0].gate == "done"
    assert r.tool_calls[0].args == {"answer": "ok"}
    assert r.usage["prompt_tokens"] == 11
    assert r.usage["completion_tokens"] == 7
    assert r.usage["provider_latency_ms"] >= 1


def test_openai_compat_raises_provider_error(monkeypatch: pytest.MonkeyPatch) -> None:
    def _post(*_args, **_kwargs):
        return _Resp(429, {"error": {"message": "rate limit"}})

    monkeypatch.setattr("cantrip.providers.openai_compat.requests.post", _post)
    c = OpenAICompatLLM(
        model="gpt-test", base_url="https://example.com", api_key="x"
    )

    with pytest.raises(ProviderError) as exc_info:
        c.query(messages=[{"role": "user", "content": "x"}], tools=[], tool_choice=None)
    assert exc_info.value.status_code == 429
    assert exc_info.value.message == "rate limit"


def test_openai_compat_raises_provider_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    from cantrip.providers import openai_compat as mod

    def _post(*_args, **_kwargs):
        raise mod.requests.exceptions.Timeout("timed out")

    monkeypatch.setattr("cantrip.providers.openai_compat.requests.post", _post)
    c = OpenAICompatLLM(
        model="gpt-test", base_url="https://example.com", api_key="x"
    )

    with pytest.raises(ProviderTimeout) as exc_info:
        c.query(messages=[{"role": "user", "content": "x"}], tools=[], tool_choice=None)
    assert "timed out" in exc_info.value.message


def test_openai_compat_raises_provider_transport_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from cantrip.providers import openai_compat as mod

    def _post(*_args, **_kwargs):
        raise mod.requests.exceptions.ConnectionError("conn reset")

    monkeypatch.setattr("cantrip.providers.openai_compat.requests.post", _post)
    c = OpenAICompatLLM(
        model="gpt-test", base_url="https://example.com", api_key="x"
    )

    with pytest.raises(ProviderTransportError) as exc_info:
        c.query(messages=[{"role": "user", "content": "x"}], tools=[], tool_choice=None)
    assert "conn reset" in exc_info.value.message


def test_tool_description_is_sent(monkeypatch) -> None:
    """Tool descriptions must be included in the API payload."""
    captured: dict = {}

    class FakeResp:
        status_code = 200

        def json(self):
            return {
                "choices": [
                    {
                        "message": {
                            "content": "ok",
                            "tool_calls": None,
                        },
                        "finish_reason": "stop",
                    }
                ],
                "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
            }

    def fake_post(url, *, headers=None, json=None, timeout=None):
        captured["json"] = json
        return FakeResp()

    import requests

    monkeypatch.setattr(requests, "post", fake_post)

    from cantrip.providers.openai_compat import OpenAICompatLLM

    llm = OpenAICompatLLM(model="test", base_url="http://fake", api_key="k")
    tools = [{"name": "echo", "description": "Echo back the input", "parameters": {"type": "object"}}]
    llm.query(messages=[{"role": "user", "content": "hi"}], tools=tools, tool_choice="auto")

    sent_tools = captured["json"]["tools"]
    assert len(sent_tools) == 1
    func = sent_tools[0]["function"]
    assert "description" in func, "Tool description must be sent to the API"
    assert func["description"] == "Echo back the input"
