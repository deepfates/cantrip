from __future__ import annotations

import json

import pytest

from cantrip.errors import CantripError
from cantrip.providers.openai_compat import OpenAICompatCrystal


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
                                    "function": {"name": "done", "arguments": '{"answer":"ok"}'},
                                }
                            ],
                        }
                    }
                ],
                "usage": {"prompt_tokens": 11, "completion_tokens": 7},
            },
        )

    monkeypatch.setattr("cantrip.providers.openai_compat.requests.post", _post)
    c = OpenAICompatCrystal(model="gpt-test", base_url="https://example.com", api_key="x")
    r = c.query(messages=[{"role": "user", "content": "x"}], tools=[{"name": "done", "parameters": {}}], tool_choice="required")

    assert r.content == "hi"
    assert r.tool_calls and r.tool_calls[0].gate == "done"
    assert r.tool_calls[0].args == {"answer": "ok"}
    assert r.usage == {"prompt_tokens": 11, "completion_tokens": 7}


def test_openai_compat_raises_provider_error(monkeypatch: pytest.MonkeyPatch) -> None:
    def _post(*_args, **_kwargs):
        return _Resp(429, {"error": {"message": "rate limit"}})

    monkeypatch.setattr("cantrip.providers.openai_compat.requests.post", _post)
    c = OpenAICompatCrystal(model="gpt-test", base_url="https://example.com", api_key="x")

    with pytest.raises(CantripError, match=r"provider_error:429:rate limit"):
        c.query(messages=[{"role": "user", "content": "x"}], tools=[], tool_choice=None)
