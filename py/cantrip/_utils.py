"""Shared internal helpers used across cantrip modules."""

from __future__ import annotations

import os


def _debug_enabled() -> bool:
    return bool(os.getenv("CANTRIP_ACP_DEBUG") or os.getenv("CANTRIP_ACP_DEBUG_FILE"))


def _debug_log(line: str) -> None:
    if not _debug_enabled():
        return
    path = os.getenv("CANTRIP_ACP_DEBUG_FILE", ".cantrip_acp_debug.log")
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(line.rstrip("\n") + "\n")
    except Exception:  # noqa: BLE001
        pass


def compose_intent(
    transcript: list[tuple[str, str]], intent: str, *, window: int = 8
) -> str:
    """Build a composed intent from conversation history.

    Used by both Entity.send() and CantripACPServer to prepend recent
    conversation context to a new user intent.
    """
    if not transcript:
        return intent

    lines = ["Conversation so far:"]
    for user_msg, assistant_msg in transcript[-window:]:
        lines.append(f"User: {user_msg}")
        if assistant_msg:
            lines.append(f"Assistant: {assistant_msg}")
    lines.append(f"User: {intent}")
    lines.append("Assistant:")
    return "\n".join(lines)
