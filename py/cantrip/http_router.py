from __future__ import annotations

from typing import Any

from cantrip.runtime import Cantrip


class CantripHTTPRouter:
    """Thin HTTP-style request router over Cantrip runtime behavior."""

    def __init__(self, cantrip: Cantrip) -> None:
        self.cantrip = cantrip

    def handle_cast(self, body: dict[str, Any]) -> dict[str, Any]:
        intent = body.get("intent")
        if not isinstance(intent, str) or not intent:
            return {
                "status": 400,
                "body": {
                    "error": {
                        "code": "invalid_request",
                        "message": "intent is required",
                    }
                },
            }
        result, thread = self.cantrip.cast_with_thread(intent)
        return {
            "status": 200,
            "body": {
                "result": result,
                "thread_id": thread.id,
            },
        }

    def handle_cast_stream(self, body: dict[str, Any]) -> dict[str, Any]:
        intent = body.get("intent")
        if not isinstance(intent, str) or not intent:
            return {
                "status": 400,
                "body": {
                    "error": {
                        "code": "invalid_request",
                        "message": "intent is required",
                    }
                },
            }
        return {
            "status": 200,
            "body": {"events": list(self.cantrip.cast_stream(intent))},
        }
