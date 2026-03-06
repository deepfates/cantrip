"""Pattern 03: Circle — the entity's capability envelope.

A circle = medium + gates + wards. It defines what an entity can do (CIRCLE-1).
Circle validates at construction time:
  - Must include a done gate (CIRCLE-1)
  - Must include at least one truncation ward (CIRCLE-2)

This example builds a valid circle, then shows both rejection cases.
"""
from __future__ import annotations

from typing import Any

from cantrip import Cantrip, CantripError, Circle, FakeLLM, Identity


def run(mode: str | None = None) -> dict[str, Any]:
    _ = mode  # No real LLM needed — circle validation is construction-time.

    print("=== Pattern 03: Circle ===")
    print("A circle = medium + gates + wards. It defines the entity's sandbox.\n")

    # --- Valid circle: echo gate + done gate, max_turns ward ---
    # CIRCLE-1: gates define what the entity can invoke.
    # CIRCLE-2: wards constrain the entity's behavior.
    valid_circle = Circle(
        gates=[{"name": "echo"}, "done"],
        wards=[{"max_turns": 5}],
        medium="tool",
    )
    gate_names = sorted(valid_circle.available_gates().keys())
    print(f"Valid circle gates: {gate_names}")
    print(f"Valid circle wards: {valid_circle.wards}")
    print(f"Valid circle medium: {valid_circle.medium}")

    # --- Missing done gate -> construction-time rejection (CIRCLE-1) ---
    # Validation fires when assembling the Cantrip (llm + identity + circle).
    missing_done_error: str | None = None
    try:
        Cantrip(
            llm=FakeLLM({"responses": []}),
            circle=Circle(gates=[{"name": "echo"}], wards=[{"max_turns": 5}]),
            identity=Identity(),
        )
    except CantripError as exc:
        missing_done_error = str(exc)
        print(f'\nMissing done gate error: "{missing_done_error}"')

    # --- No wards -> construction-time rejection (CIRCLE-2) ---
    missing_ward_error: str | None = None
    try:
        Cantrip(
            llm=FakeLLM({"responses": []}),
            circle=Circle(gates=["done"], wards=[]),
            identity=Identity(),
        )
    except CantripError as exc:
        missing_ward_error = str(exc)
        print(f'No wards error: "{missing_ward_error}"')

    print("\nCircle enforces invariants at construction time.")
    print("You cannot create an entity without a done gate or without wards.")

    return {
        "pattern": 3,
        "medium": valid_circle.medium,
        "gates": gate_names,
        "wards": valid_circle.wards,
        "missing_done_error": missing_done_error,
        "missing_ward_error": missing_ward_error,
    }


if __name__ == "__main__":
    import json
    print(json.dumps(run(), indent=2))
