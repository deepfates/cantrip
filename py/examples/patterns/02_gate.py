"""Pattern 02: Gate (A.2)

A gate is a typed function the entity can call.
Gates are how entities interact with the outside world.
No LLM needed — gates can be tested in isolation.

Spec ref: GATE-1 (gates define the action surface),
          GATE-DONE (done signals completion, rejects empty answers).
"""
from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity


def run(mode: str | None = None) -> dict[str, Any]:
    _ = mode

    print("=== Pattern 02: Gate ===")
    print("A gate is a typed function the entity can call.\n")

    # Construct a circle with echo + done gates (GATE-1).
    # The circle defines what gates exist; wards constrain them.
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

    # Inspect the gate registry — available_gates() shows what the entity can call.
    gates = circle.available_gates()
    gate_names = sorted(gates.keys())
    print(f"Gates in this circle: {gate_names}")

    # Drive the echo gate through a cast: FakeLLM calls echo, then done.
    print("\nCalling echo gate, then done gate...")
    echo_llm = FakeLLM({"responses": [
        {"tool_calls": [{"gate": "echo", "args": {"text": "hello from gate"}}]},
        {"tool_calls": [{"gate": "done", "args": {"answer": "finished"}}]},
    ]})
    cantrip = Cantrip(llm=echo_llm, circle=circle, identity=Identity())
    result, thread = cantrip.cast_with_thread("Demonstrate echo then done.")

    # The first turn used echo; the second used done.
    echo_result = thread.turns[0].observation[0].result
    done_result = result
    print(f"echo returned: {echo_result}")
    print(f"done returned: {done_result}")

    # The done gate has special behavior: it rejects empty answers (GATE-DONE).
    # This prevents the entity from completing without actually answering.
    print("\nTesting done gate rejection of empty answers...")
    empty_llm = FakeLLM({"responses": [
        {"tool_calls": [{"gate": "done", "args": {"answer": "   "}}]},
        {"tool_calls": [{"gate": "done", "args": {"answer": "recovered"}}]},
    ]})
    cantrip2 = Cantrip(llm=empty_llm, circle=circle, identity=Identity())
    _, thread2 = cantrip2.cast_with_thread("Try empty done then recover.")
    done_bad = thread2.turns[0].observation[0]
    print(f"Empty answer rejected: {done_bad.is_error}")
    print(f"Error message: {done_bad.content}")

    print("\nGates are just functions with metadata. The entity sees them as tools.")

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
