"""Pattern 11: Persistent Entity — summon once, send repeatedly, state accumulates.

The entity remembers prior exchanges. The second send benefits from the first
because Entity.send() composes a transcript of prior turns into the intent (ENTITY-1).
This is the summon/send pattern: one cantrip, one entity, multiple intents over time.
"""
from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, Identity

from ._llm import resolve_llm

# --- Scripted responses for CI (FakeLLM) ---
# First send: entity gathers key metrics from the data.
# Second send: entity builds on the first answer to give a recommendation.
SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [
            {
                "gate": "done",
                "args": {
                    "answer": (
                        "Key metrics: Revenue grew 14% QoQ to $4.2M. "
                        "Churn dropped from 6.1% to 4.0%. "
                        "Net new ARR is $580K. CAC payback improved to 11 months."
                    ),
                },
            }
        ]
    },
    {
        "tool_calls": [
            {
                "gate": "done",
                "args": {
                    "answer": (
                        "Recommendation: Double down on the current acquisition channel. "
                        "The 14% revenue growth combined with the 2-point churn improvement "
                        "means net retention is accelerating. With CAC payback at 11 months, "
                        "increasing spend is ROI-positive within the fiscal year."
                    ),
                },
            }
        ]
    },
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 11: summon once, send repeatedly, state accumulates (ENTITY-1)."""

    llm = resolve_llm(mode, scripted_responses=SCRIPTED_RESPONSES)

    # -- Construct the cantrip: done gate + max_turns ward (CIRCLE-1, WARD-1) --
    spell = Cantrip(
        llm=llm,
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}]),
        identity=Identity(
            system_prompt=(
                "You are a SaaS metrics analyst. "
                "When given data, extract key metrics. "
                "When asked for recommendations, reference your prior analysis. "
                "Always finish by calling done(answer)."
            )
        ),
    )

    # -- Summon: creates a persistent entity (ENTITY-1) --
    entity = spell.summon()

    print("=== Pattern 11: Persistent Entity ===")
    print("Summon once, send repeatedly. State accumulates across sends.\n")

    # -- First send: gather metrics --
    data = (
        "Q3 results: Revenue $4.2M (up 14% QoQ), churn 4.0% (was 6.1%), "
        "net new ARR $580K, CAC payback 11 months."
    )
    print(f"[Send 1] Analyze this data:\n  {data}")
    first = entity.send(f"Extract the key metrics from this data: {data}")
    print(f"  -> {first}\n")

    # -- State check: entity has accumulated turns --
    turns_after_first = len(entity.turns)
    print(f"  Accumulated turns after first send: {turns_after_first}")

    # -- Second send: build on the first answer --
    print("\n[Send 2] Now ask for a recommendation based on the prior analysis:")
    second = entity.send(
        "Based on the metrics you just extracted, what is your top recommendation?"
    )
    print(f"  -> {second}\n")

    turns_after_second = len(entity.turns)
    print(f"  Accumulated turns after second send: {turns_after_second}")
    print(f"  Last thread turns: {len(entity.last_thread.turns) if entity.last_thread else 0}")
    print("\nThe second answer references the first because Entity.send() composes")
    print("a transcript of prior exchanges into each new intent (ENTITY-1).")

    return {
        "pattern": 11,
        "first": first,
        "second": second,
        "accumulated_turns": turns_after_second,
        "last_thread_turns": len(entity.last_thread.turns) if entity.last_thread else 0,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
