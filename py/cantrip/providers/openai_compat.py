from __future__ import annotations

import json
import os
from typing import Any

try:
    import requests
except Exception:  # pragma: no cover
    requests = None

from cantrip.errors import CantripError
from cantrip.models import CrystalResponse, ToolCall
from cantrip.providers.base import Crystal


class OpenAICompatCrystal(Crystal):
    """OpenAI-compatible chat completions client.

    Works with OpenAI, Ollama, vLLM and other compatible servers.
    """

    def __init__(
        self,
        *,
        model: str,
        base_url: str | None = None,
        api_key: str | None = None,
        timeout_s: float = 60.0,
        extra: dict[str, Any] | None = None,
    ) -> None:
        self.model = model
        self.base_url = (base_url or os.getenv("OPENAI_BASE_URL") or "https://api.openai.com/v1").rstrip("/")
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        self.timeout_s = timeout_s
        self.extra = extra or {}
        if requests is None:
            raise CantripError("requests dependency is required for OpenAICompatCrystal")

    def query(self, messages, tools, tool_choice):
        payload = {
            "model": self.model,
            "messages": messages,
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": t["name"],
                        "parameters": t.get("parameters") or {"type": "object"},
                    },
                }
                for t in tools
            ],
            **self.extra,
        }
        if tool_choice is not None:
            payload["tool_choice"] = tool_choice

        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        resp = requests.post(
            f"{self.base_url}/chat/completions",
            headers=headers,
            data=json.dumps(payload),
            timeout=self.timeout_s,
        )
        if resp.status_code >= 400:
            try:
                msg = resp.json().get("error", {}).get("message", resp.text)
            except Exception:  # noqa: BLE001
                msg = resp.text
            raise CantripError(f"provider_error:{resp.status_code}:{msg}")

        data = resp.json()
        choice = data["choices"][0]
        msg = choice.get("message", {})
        content = msg.get("content")

        raw_calls = msg.get("tool_calls") or []
        tool_calls = []
        for i, c in enumerate(raw_calls):
            fn = c.get("function", {})
            args_raw = fn.get("arguments") or "{}"
            try:
                args = json.loads(args_raw)
            except Exception:  # noqa: BLE001
                args = {}
            tool_calls.append(
                ToolCall(
                    id=c.get("id") or f"call_{i+1}",
                    gate=fn.get("name"),
                    args=args,
                )
            )

        usage = data.get("usage") or {}
        return CrystalResponse(
            content=content,
            tool_calls=tool_calls,
            usage={
                "prompt_tokens": int(usage.get("prompt_tokens", 0)),
                "completion_tokens": int(usage.get("completion_tokens", 0)),
            },
        )
