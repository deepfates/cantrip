"""Persistent entity created by summoning a cantrip."""

from __future__ import annotations

import copy
from typing import Any
from uuid import uuid4

from .models import Thread, Turn


class Entity:
    """A persistent entity created by summoning a cantrip.

    Wraps a Cantrip and accumulates state (turns) across multiple
    send() calls, implementing the summon/send pattern from the spec.
    """

    def __init__(self, cantrip: Any) -> None:
        self._cantrip = cantrip
        self._seed_turns: list[Turn] = []
        self._transcript: list[tuple[str, str]] = []
        self._last_thread: Thread | None = None
        self.entity_id: str = str(uuid4())

    def send(self, intent: str, *, compose_intent: bool = True, **kwargs: Any) -> Any:
        """Send an intent to this entity. State accumulates across calls."""
        composed_intent = intent
        if compose_intent and self._transcript:
            lines = ["Conversation so far:"]
            for user_msg, assistant_msg in self._transcript[-8:]:
                lines.append(f"User: {user_msg}")
                if assistant_msg:
                    lines.append(f"Assistant: {assistant_msg}")
            lines.append(f"User: {intent}")
            lines.append("Assistant:")
            composed_intent = "\n".join(lines)

        result, thread = self._cantrip.cast_with_thread(
            intent=composed_intent, seed_turns=self._seed_turns, **kwargs
        )
        thread.entity_id = self.entity_id
        for turn in thread.turns:
            turn.entity_id = self.entity_id
        self._seed_turns = copy.deepcopy(thread.turns)
        self._last_thread = thread
        self._transcript.append((intent, str(result or "").strip()))
        return result

    @property
    def turns(self) -> list[Turn]:
        """The accumulated turns from all episodes."""
        return list(self._seed_turns)

    @property
    def last_thread(self) -> Thread | None:
        """Most recent thread produced by send()."""
        return self._last_thread
