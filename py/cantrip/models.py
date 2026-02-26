from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class Call:
    system_prompt: str | None = None
    temperature: float | None = None
    require_done_tool: bool = False
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


@dataclass
class Circle:
    gates: list[Any]
    wards: list[dict[str, Any]]
    medium: str = "tool"
    depends: dict[str, Any] | None = None
    filesystem: dict[str, str] | None = None

    def __post_init__(self) -> None:
        self._gates: dict[str, Gate] = {}
<<<<<<< HEAD
        for g in self.gates:
            if isinstance(g, str):
                self._gates[g] = Gate(name=g)
            else:
                self._gates[g["name"]] = Gate(
                    name=g["name"],
=======
        # Map call_agent -> call_entity aliases
        _GATE_ALIASES = {
            "call_agent": "call_entity",
            "call_agent_batch": "call_entity_batch",
        }
        for g in self.gates:
            if isinstance(g, str):
                canonical = _GATE_ALIASES.get(g, g)
                self._gates[canonical] = Gate(name=canonical)
            else:
                canonical_name = _GATE_ALIASES.get(g["name"], g["name"])
                self._gates[canonical_name] = Gate(
                    name=canonical_name,
>>>>>>> monorepo/main
                    parameters=g.get("parameters"),
                    behavior=g.get("behavior"),
                    delay_ms=g.get("delay_ms"),
                    result=g.get("result"),
                    error=g.get("error"),
<<<<<<< HEAD
                    depends=g.get("depends"),
=======
                    depends=g.get("depends") or g.get("dependencies"),
>>>>>>> monorepo/main
                    ephemeral=bool(g.get("ephemeral", False)),
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

    def removed_gates(self) -> set[str]:
        removed = set()
        for w in self.wards:
            if "remove_gate" in w:
                removed.add(str(w["remove_gate"]))
        return removed

    def available_gates(self) -> dict[str, Gate]:
        removed = self.removed_gates()
        gates = {k: v for k, v in self._gates.items() if k not in removed}
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
class CrystalResponse:
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
    call: Call
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
