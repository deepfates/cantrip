from __future__ import annotations

import json
from typing import Any

from cantrip.runtime import Cantrip


def run_cli(cantrip: Cantrip, *, intent: str) -> dict[str, Any]:
    """Thin CLI contract: execute one cast and return machine-readable payload."""
    result, thread = cantrip.cast_with_thread(intent)
    return {"result": result, "thread_id": thread.id}


def format_cli_json(payload: dict[str, Any]) -> str:
    return json.dumps(payload)
