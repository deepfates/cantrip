"""Pattern 04: Cantrip — the reusable spell definition.

A cantrip = llm + identity + circle (CANTRIP-1).
Each cast() produces an independent entity with its own thread.
Same configuration, independent executions — like a function you can call twice.
"""
from __future__ import annotations

from typing import Any

from cantrip import Cantrip, Circle, Identity

from ._llm import resolve_llm

# Scripted responses for CI: two independent casts, each calls done immediately.
SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "Revenue grew 14% QoQ, driven by enterprise expansion. Churn dropped 2pp, suggesting improved retention."}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "COGS rose 8% but gross margin improved 3pp due to pricing leverage. OpEx flat YoY."}}]},
]


def run(mode: str | None = None) -> dict[str, Any]:
    print("=== Pattern 04: Cantrip ===")
    print("A cantrip = llm + identity + circle. Each cast is independent.\n")

    # CANTRIP-1: Assemble the three components into a reusable spell.
    spell = Cantrip(
        llm=resolve_llm(mode, scripted_responses=SCRIPTED_RESPONSES),
        identity=Identity(
            system_prompt=(
                "You are a financial analyst. Analyze the data provided and identify "
                "the key trend. Call done(answer) with a concise summary."
            )
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 4}]),
    )

    print("Cantrip assembled: same config will be used for both casts.")

    # Cast 1: analyze revenue trends
    print("\n--- Cast 1: Revenue analysis ---")
    result_1, thread_1 = spell.cast_with_thread(
        "Analyze this quarterly data and identify the key trend: "
        "Revenue up 14% QoQ, churn down 2 percentage points, "
        "enterprise seats grew 31%."
    )
    print(f"Thread ID: {thread_1.id}")
    print(f"Turns: {len(thread_1.turns)}")
    print(f"Result: {result_1}")

    # Cast 2: analyze cost structure — completely independent
    print("\n--- Cast 2: Cost analysis ---")
    result_2, thread_2 = spell.cast_with_thread(
        "Analyze this quarterly data and identify the key trend: "
        "COGS up 8%, gross margin improved 3pp, OpEx flat YoY."
    )
    print(f"Thread ID: {thread_2.id}")
    print(f"Turns: {len(thread_2.turns)}")
    print(f"Result: {result_2}")

    # Key insight: same cantrip, independent threads.
    independent = thread_1.id != thread_2.id
    print(f"\nIndependent threads: {independent}")
    print("Each cast creates a fresh entity — no shared state between them.")

    return {
        "pattern": 4,
        "result_1": result_1,
        "result_2": result_2,
        "thread_ids": [thread_1.id, thread_2.id],
        "independent_threads": independent,
        "turn_counts": [len(thread_1.turns), len(thread_2.turns)],
    }


if __name__ == "__main__":
    import json
    print(json.dumps(run(), indent=2))
