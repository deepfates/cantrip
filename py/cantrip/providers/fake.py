from __future__ import annotations

import copy
import threading

from cantrip.errors import CantripError
from cantrip.models import CrystalResponse, ToolCall
from cantrip.providers.base import Crystal


class FakeCrystal(Crystal):
    """Deterministic crystal used for tests and local simulation."""

    def __init__(self, spec: dict | None = None):
        spec = spec or {}
        self.spec = spec
        self.responses = copy.deepcopy(spec.get("responses", []))
        self.index = 0
        self.record_inputs = bool(spec.get("record_inputs", False))
        self.invocations: list[dict] = []
        self.default_usage = spec.get("usage")
        self.provider = spec.get("provider")
        self.raw_response = spec.get("raw_response")
        self._lock = threading.Lock()

    def _next_raw(self) -> dict:
<<<<<<< HEAD
        if self.provider == "mock_openai" and self.raw_response:
=======
        if self.provider == "mock_openai" and self.raw_response and not self.responses:
>>>>>>> monorepo/main
            return copy.deepcopy(self.raw_response)
        if self.index >= len(self.responses):
            return {"content": ""}
        item = copy.deepcopy(self.responses[self.index])
        self.index += 1
        return item

    def query(self, messages, tools, tool_choice):
        with self._lock:
            self.invocations.append(
                {
                    "messages": copy.deepcopy(messages),
                    "tools": copy.deepcopy(tools),
                    "tool_choice": tool_choice,
                }
            )
            raw = self._next_raw()

        if "error" in raw:
            err = raw["error"]
            raise CantripError(
                f"provider_error:{err.get('status')}:{err.get('message')}"
            )

<<<<<<< HEAD
        if self.provider == "mock_openai" and self.raw_response:
=======
        # Handle tool_result response type (validates tool call ID linkage)
        if "tool_result" in raw:
            tool_result = raw["tool_result"]
            tool_call_id = tool_result.get("tool_call_id")
            # Check if there's a matching tool call in the messages
            has_match = False
            for msg in messages:
                if msg.get("role") == "assistant":
                    for tc in (msg.get("tool_calls") or []):
                        tc_id = tc.get("id") if isinstance(tc, dict) else None
                        if tc_id == tool_call_id:
                            has_match = True
                            break
            if not has_match:
                raise CantripError("tool result without matching tool call")
            return CrystalResponse(
                content=tool_result.get("content"),
                tool_calls=None,
                usage=raw.get("usage"),
            )

        if self.provider == "mock_openai" and self.raw_response and "choices" in raw:
>>>>>>> monorepo/main
            choice = raw["choices"][0]
            msg = choice["message"]
            usage = raw.get("usage", {})
            return CrystalResponse(
                content=msg.get("content"),
                tool_calls=[],
                usage={
                    "prompt_tokens": int(usage.get("prompt_tokens", 0)),
                    "completion_tokens": int(usage.get("completion_tokens", 0)),
                },
            )

        calls = None
        if raw.get("tool_calls") is not None:
            calls = []
            for i, c in enumerate(raw.get("tool_calls", [])):
                calls.append(
                    ToolCall(
                        id=c.get("id") or f"call_{i+1}",
                        gate=c.get("gate") or c.get("name"),
                        args=copy.deepcopy(c.get("args", {})),
                    )
                )

        usage = raw.get("usage") or self.default_usage
        content = raw.get("content")
        if content is None and raw.get("code") is not None:
            content = raw.get("code")
        return CrystalResponse(content=content, tool_calls=calls, usage=usage)
