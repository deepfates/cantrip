from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, CantripError, Circle, FakeLLM, Identity


def run(mode: str | None = None) -> dict[str, Any]:
    _ = mode
    # Pattern 3: circle + wards assembled explicitly.
    valid_circle = Circle(
        gates=[{"name": "echo"}, "done"],
        wards=[{"max_turns": 5}],
        medium="tool",
    )

    missing_done_error: str | None = None
    try:
        # Construction-time rejection: no done gate.
        Cantrip(
            llm=FakeLLM({"responses": []}),
            circle=Circle(gates=[{"name": "echo"}], wards=[{"max_turns": 5}]),
            identity=Identity(),
        )
    except CantripError as exc:
        missing_done_error = str(exc)

    missing_ward_error: str | None = None
    try:
        # Construction-time rejection: no truncation ward.
        Cantrip(
            llm=FakeLLM({"responses": []}),
            circle=Circle(gates=["done"], wards=[]),
            identity=Identity(),
        )
    except CantripError as exc:
        missing_ward_error = str(exc)

    return {
        "pattern": 3,
        "medium": valid_circle.medium,
        "gates": sorted(valid_circle.available_gates().keys()),
        "wards": valid_circle.wards,
        "missing_done_error": missing_done_error,
        "missing_ward_error": missing_ward_error,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
