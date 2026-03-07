from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class Identity:
    system_prompt: str | None = None
    temperature: float | None = None
    tool_choice: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)




@dataclass
class Gate:
    name: str
    parameters: dict[str, Any] | None = None
    behavior: str | None = None
    delay_ms: int | None = None
    result: Any = None
    error: str | None = None
    depends: dict[str, Any] | None = None
    ephemeral: bool = False


# Default schema for the "done" gate so LLMs know `answer` is required.
_DONE_PARAMETERS: dict[str, Any] = {
    "type": "object",
    "properties": {"answer": {"type": "string", "description": "Your final answer"}},
    "required": ["answer"],
}


@dataclass
class Circle:
    gates: list[Any]
    wards: list[dict[str, Any]]
    medium: str = "tool"
    depends: dict[str, Any] | None = None
    filesystem: dict[str, str] | None = None

    def __post_init__(self) -> None:
        self._gates: dict[str, Gate] = {}
        for g in self.gates:
            if isinstance(g, str):
                self._gates[g] = Gate(
                    name=g,
                    parameters=_DONE_PARAMETERS if g == "done" else None,
                )
            else:
                params = g.get("parameters")
                if params is None and g["name"] == "done":
                    params = _DONE_PARAMETERS
                self._gates[g["name"]] = Gate(
                    name=g["name"],
                    parameters=params,
                    behavior=g.get("behavior"),
                    delay_ms=g.get("delay_ms"),
                    result=g.get("result"),
                    error=g.get("error"),
                    depends=g.get("depends", g.get("dependencies")),
                    ephemeral=bool(g.get("ephemeral", False)),
                )

    def require_done_tool(self) -> bool:
        """OR composition: if any ward has require_done_tool=True, result is True."""
        return any(
            bool(w.get("require_done_tool"))
            for w in self.wards
            if "require_done_tool" in w
        )

    def max_turns(self) -> int | None:
        for w in self.wards:
            if "max_turns" in w:
                return int(w["max_turns"])
        return None

    def max_depth(self) -> int | None:
        for w in self.wards:
            if "max_depth" in w:
                return int(w["max_depth"])
        return None

    def available_gates(self) -> dict[str, Gate]:
        gates = dict(self._gates)
        max_depth = self.max_depth()
        if max_depth is not None and max_depth <= 0:
            gates.pop("call_entity", None)
            gates.pop("call_entity_batch", None)
        return gates


@dataclass
class ToolCall:
    id: str
    gate: str
    args: dict[str, Any]


@dataclass
class LLMResponse:
    content: str | None = None
    tool_calls: list[ToolCall] | None = None
    usage: dict[str, int] | None = None


@dataclass
class GateCallRecord:
    gate_name: str
    arguments: dict[str, Any]
    result: Any = None
    is_error: bool = False
    content: str = ""
    ephemeral: bool = False


@dataclass
class Turn:
    id: str
    entity_id: str
    sequence: int
    parent_id: str | None
    utterance: dict[str, Any]
    observation: list[GateCallRecord]
    terminated: bool = False
    truncated: bool = False
    reward: float | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class Thread:
    id: str
    entity_id: str
    intent: str
    identity: Identity
    turns: list[Turn] = field(default_factory=list)
    result: Any = None
    terminated: bool = False
    truncated: bool = False
    cumulative_usage: dict[str, int] = field(
        default_factory=lambda: {
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
        }
    )
