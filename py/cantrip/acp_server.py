from __future__ import annotations

import copy
import uuid
from dataclasses import dataclass, field
from typing import Any

from cantrip.models import Turn
from cantrip.runtime import Cantrip


@dataclass
class _SessionState:
    seed_turns: list[Turn] = field(default_factory=list)
    transcript: list[tuple[str, str]] = field(default_factory=list)


class CantripACPServer:
    """Thin ACP-facing wrapper over Cantrip runtime semantics.

    This module intentionally does not implement network transport. It provides
    protocol-shaped lifecycle methods while delegating all behavior to Cantrip.
    """

    def __init__(self, cantrip: Cantrip) -> None:
        self.cantrip = cantrip
        self._sessions: dict[str, _SessionState] = {}

    def create_session(self) -> str:
        session_id = str(uuid.uuid4())
        self._sessions[session_id] = _SessionState()
        return session_id

    def session_exists(self, session_id: str) -> bool:
        return session_id in self._sessions

    def close_session(self, session_id: str) -> bool:
        if session_id not in self._sessions:
            return False
        self._sessions.pop(session_id, None)
        return True

    def cast(self, *, session_id: str, intent: str) -> dict[str, Any]:
        state = self._sessions.get(session_id)
        if state is None:
            raise KeyError(f"unknown session: {session_id}")

        composed_intent = self._compose_intent(state, intent)
        result, thread = self.cantrip.cast_with_thread(
            intent=composed_intent, seed_turns=state.seed_turns
        )
        state.seed_turns = copy.deepcopy(thread.turns)
        assistant_text = self._assistant_text_from_outcome(thread, result)
        state.transcript.append((intent, assistant_text))
        events = self._events_from_thread(thread, result)
        return {
            "session_id": session_id,
            "thread_id": thread.id,
            "result": result,
            "assistant_text": assistant_text,
            "events": events,
        }

    def _assistant_text_from_outcome(self, thread, result: Any) -> str:
        if result is not None and str(result).strip():
            return str(result)
        if thread.truncated:
            return "No final answer produced before max_turns."
        for turn in reversed(thread.turns):
            for rec in reversed(turn.observation):
                if rec.is_error and rec.content:
                    return f"No final answer produced. Last error: {rec.content}"
        if result is None:
            return "No final answer produced."
        return ""

    def _compose_intent(self, state: _SessionState, intent: str) -> str:
        if not state.transcript:
            return intent

        lines = ["Conversation so far:"]
        for user_msg, assistant_msg in state.transcript[-8:]:
            lines.append(f"User: {user_msg}")
            if assistant_msg:
                lines.append(f"Assistant: {assistant_msg}")
        lines.append(f"User: {intent}")
        lines.append("Assistant:")
        return "\n".join(lines)

    def _events_from_thread(self, thread, result: Any) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        for turn in thread.turns:
            events.append(
                {"type": "step_start", "turn_id": turn.id, "sequence": turn.sequence}
            )
            if turn.utterance.get("content"):
                events.append(
                    {
                        "type": "text",
                        "turn_id": turn.id,
                        "content": turn.utterance["content"],
                    }
                )
            for rec in turn.observation:
                events.append(
                    {
                        "type": "tool_result",
                        "turn_id": turn.id,
                        "gate": rec.gate_name,
                        "is_error": rec.is_error,
                        "result": rec.result,
                        "content": rec.content,
                    }
                )
            events.append(
                {"type": "step_complete", "turn_id": turn.id, "sequence": turn.sequence}
            )
        events.append(
            {"type": "final_response", "result": result, "thread_id": thread.id}
        )
        return events
