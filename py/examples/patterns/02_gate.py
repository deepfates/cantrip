from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, Loom
from cantrip.models import Thread
from cantrip.providers.base import LLM


@dataclass(frozen=True)
class GateExample:
    name: str
    parameters: dict[str, Any]


ECHO_GATE = GateExample(
    name="echo",
    parameters={
        "type": "object",
        "properties": {"text": {"type": "string"}},
        "required": ["text"],
    },
)


def run(llm: LLM | None = None) -> dict[str, Any]:
    _ = llm
    # Pattern 2: gates are metadata + executable behavior.
    circle = Circle(gates=[{"name": ECHO_GATE.name, "parameters": ECHO_GATE.parameters}, "done"], wards=[{"max_turns": 3}])
    cantrip = Cantrip(llm=FakeLLM({"responses": []}), circle=circle, identity=Identity())
    thread = Thread(id="gate-thread", entity_id="gate-entity", intent="demo", identity=Identity())

    echo_call = cantrip._execute_gate(
        thread,
        "echo",
        {"text": "hello from gate"},
        parent_turn_id=None,
        circle=circle,
        depth=None,
    )
    done_ok = cantrip._execute_gate(
        thread,
        "done",
        {"answer": "finished"},
        parent_turn_id=None,
        circle=circle,
        depth=None,
    )
    done_bad = cantrip._execute_gate(
        thread,
        "done",
        {"answer": "   "},
        parent_turn_id=None,
        circle=circle,
        depth=None,
    )

    return {
        "pattern": 2,
        "gate_name": ECHO_GATE.name,
        "echo_result": echo_call.result,
        "done_result": done_ok.result,
        "done_rejects_empty": done_bad.is_error,
        "done_error": done_bad.content,
        "loom_turns": len(Loom().turns),
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
