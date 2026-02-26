from __future__ import annotations

import copy
import time
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

from cantrip.models import Turn
from cantrip.runtime import Cantrip


@dataclass
class _SessionState:
    seed_turns: list[Turn] = field(default_factory=list)
    transcript: list[tuple[str, str]] = field(default_factory=list)
    cancel_requested: bool = False


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

    def cast(
        self,
        *,
        session_id: str,
        intent: str,
        event_sink: Callable[[dict[str, Any]], None] | None = None,
    ) -> dict[str, Any]:
        state = self._sessions.get(session_id)
        if state is None:
            raise KeyError(f"unknown session: {session_id}")

        prior_turn_count = len(state.seed_turns)
        composed_intent = self._compose_intent(state, intent)
        state.cancel_requested = False
        started = time.perf_counter()
        result, thread = self.cantrip.cast_with_thread(
            intent=composed_intent,
            seed_turns=state.seed_turns,
            event_sink=event_sink,
            cancel_check=lambda: bool(state.cancel_requested),
        )
        cast_ms = max(1, int((time.perf_counter() - started) * 1000))
        state.cancel_requested = False
        state.seed_turns = copy.deepcopy(thread.turns)
        assistant_text = self._assistant_text_from_outcome(thread, result)
        state.transcript.append((intent, assistant_text))
        events = self._events_from_thread(
            thread, result, start_turn_index=prior_turn_count
        )
        timing = self._timing_summary(thread, start_turn_index=prior_turn_count)
        timing["cast_ms"] = cast_ms
        return {
            "session_id": session_id,
            "thread_id": thread.id,
            "result": result,
            "assistant_text": assistant_text,
            "stop_reason": self._stop_reason_from_outcome(thread),
            "events": events,
            "timing": timing,
        }

    def _timing_summary(
        self, thread, *, start_turn_index: int = 0
    ) -> dict[str, int | None]:
        turns = thread.turns[start_turn_index:]
        turn_duration_ms = 0
        provider_latency_ms = 0
        provider_seen = False
        for turn in turns:
            try:
                turn_duration_ms += int(turn.metadata.get("duration_ms", 0))
            except Exception:  # noqa: BLE001
                pass
            provider_ms = turn.metadata.get("provider_latency_ms")
            if provider_ms is not None:
                provider_seen = True
                try:
                    provider_latency_ms += int(provider_ms)
                except Exception:  # noqa: BLE001
                    pass
        return {
            "turns": len(turns),
            "turn_duration_ms": turn_duration_ms,
            "provider_latency_ms": provider_latency_ms if provider_seen else None,
        }

    def _assistant_text_from_outcome(self, thread, result: Any) -> str:
        if result is not None and str(result).strip():
            return str(result)
        if bool(getattr(thread, "cancelled", False)):
            return "Cancelled."
        if thread.truncated:
            last_error = None
            for turn in reversed(thread.turns):
                for rec in reversed(turn.observation):
                    if rec.is_error and rec.content:
                        last_error = str(rec.content)
                        break
                if last_error:
                    break
            if last_error:
                return (
                    "No final answer produced before max_turns. "
                    f"Last error: {last_error}"
                )
            return "No final answer produced before max_turns."
        for turn in reversed(thread.turns):
            for rec in reversed(turn.observation):
                if rec.is_error and rec.content:
                    return f"No final answer produced. Last error: {rec.content}"
        if result is None:
            return "No final answer produced."
        return ""

    def _stop_reason_from_outcome(self, thread) -> str:
        if bool(getattr(thread, "cancelled", False)):
            return "cancelled"
        if thread.truncated:
            if thread.turns:
                reason = thread.turns[-1].metadata.get("truncation_reason")
                if reason == "max_turns":
                    return "max_turn_requests"
            return "end_turn"
        return "end_turn"

    def request_cancel(self, session_id: str) -> bool:
        state = self._sessions.get(session_id)
        if state is None:
            return False
        state.cancel_requested = True
        return True

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

    def _events_from_thread(
        self, thread, result: Any, *, start_turn_index: int = 0
    ) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        for turn in thread.turns[start_turn_index:]:
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
                        "arguments": rec.arguments,
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
