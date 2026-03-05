from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity


def run(mode: str | None = None) -> dict[str, Any]:
    _ = mode
    # Pattern 2: gates define the action space available to the agent.
    # We construct a circle with echo + done, then inspect what gates are exposed.
    circle = Circle(
        gates=[
            {"name": "echo", "parameters": {
                "type": "object",
                "properties": {"text": {"type": "string"}},
                "required": ["text"],
            }},
            "done",
        ],
        wards=[{"max_turns": 3}],
    )

    # Public API: available_gates() returns the gate registry.
    gates = circle.available_gates()
    gate_names = sorted(gates.keys())

    # Drive the echo gate through a cast: FakeLLM calls echo, then done.
    echo_llm = FakeLLM({"responses": [
        {"tool_calls": [{"gate": "echo", "args": {"text": "hello from gate"}}]},
        {"tool_calls": [{"gate": "done", "args": {"answer": "finished"}}]},
    ]})
    cantrip = Cantrip(llm=echo_llm, circle=circle, identity=Identity())
    result, thread = cantrip.cast_with_thread("Demonstrate echo then done.")

    # The first turn used echo; the second used done.
    echo_result = thread.turns[0].observation[0].result
    done_result = result

    # Drive done with empty answer to show rejection.
    empty_llm = FakeLLM({"responses": [
        {"tool_calls": [{"gate": "done", "args": {"answer": "   "}}]},
        {"tool_calls": [{"gate": "done", "args": {"answer": "recovered"}}]},
    ]})
    cantrip2 = Cantrip(llm=empty_llm, circle=circle, identity=Identity())
    _, thread2 = cantrip2.cast_with_thread("Try empty done then recover.")
    done_bad = thread2.turns[0].observation[0]

    return {
        "pattern": 2,
        "gate_name": "echo",
        "gate_names": gate_names,
        "echo_result": echo_result,
        "done_result": done_result,
        "done_rejects_empty": done_bad.is_error,
        "done_error": done_bad.content,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
