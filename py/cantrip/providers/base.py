from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from cantrip.models import CrystalResponse


class Crystal(ABC):
    @abstractmethod
    def query(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
        tool_choice: str | None,
    ) -> CrystalResponse:
        raise NotImplementedError
