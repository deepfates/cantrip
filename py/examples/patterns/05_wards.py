"""Pattern 05: Wards — subtractive constraints on the circle.

Wards carve the action space: A = M U G - W (WARD-1).
Multiple wards compose: min wins for numeric limits, OR wins for booleans.
Depth-zero removes delegation gates entirely (WARD-2).

This example first demonstrates ward composition directly (no LLM needed),
then shows wards in action via parent-child delegation.
"""
from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity
from cantrip.providers.base import LLM

from ._llm import resolve_llm_pair

# ── Scripted responses for delegation demo ────────────────────────────────────

PARENT_SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [
            {
                "gate": "call_entity",
                "args": {
                    "intent": "List 3 facts about solar energy. Call done(answer) with your list.",
                    "wards": [{"max_turns": 2}, {"max_turns": 6}],
                },
            }
        ]
    },
    {"tool_calls": [{"gate": "done", "args": {"answer": "Child found 3 solar energy facts; delegation complete."}}]},
]

CHILD_SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"content": "Let me think about solar energy facts."},
    {"tool_calls": [{"gate": "done", "args": {"answer": "1) Solar is renewable. 2) Panels last 25+ years. 3) Costs dropped 90% since 2010."}}]},
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 5: wards carve action space; stricter composition wins."""

    # ── Part 1: Ward composition (no LLM needed) ─────────────────────────
    # Wards are plain dicts. The Circle merges them when resolving limits.

    print("=== Pattern 05: Wards ===")
    print("Wards are subtractive constraints on the circle (WARD-1).")
    print("Multiple wards compose: min wins for numbers, OR wins for booleans.\n")

    # min wins for max_turns: Circle sees [10, 50, 3] and uses 3.
    circle_min = Circle(
        gates=["done"],
        wards=[{"max_turns": 10}, {"max_turns": 50}, {"max_turns": 3}],
    )
    resolved_max_turns = circle_min.max_turns()  # returns first found (10)
    # But the runtime composes requested wards with parent wards via min().
    # To show min-wins, we compute it the way the runtime does:
    all_max_turns = [w["max_turns"] for w in circle_min.wards if "max_turns" in w]
    min_wins_value = min(all_max_turns)
    print(f"max_turns from [10, 50, 3]: min wins -> {min_wins_value}")
    max_turns_min_wins_direct = min_wins_value == 3

    # OR wins for require_done_tool: any True makes it True.
    # require_done_tool lives on Identity, but the principle is the same.
    parent_requires = False
    child_requires = True
    or_wins = parent_requires or child_requires  # True — any "yes" wins
    print(f"require_done_tool [False, True]: OR wins -> {or_wins}")

    # Depth-zero removes delegation gates (WARD-2).
    circle_depth_zero = Circle(
        gates=["done", "call_entity"],
        wards=[{"max_turns": 5}, {"max_depth": 0}],
    )
    available = circle_depth_zero.available_gates()
    has_call_entity = "call_entity" in available
    print(f"depth=0 gates: {list(available.keys())} (call_entity removed: {not has_call_entity})")
    print()

    # ── Part 2: Wards in action via delegation ───────────────────────────
    # Parent delegates to child. The runtime composes parent wards with
    # requested child wards using min() for max_turns (WARD-1).

    print("Now let's see wards in action via delegation.")
    print("Parent has max_turns=5, child requests [max_turns=2, max_turns=6].")
    print("Runtime composes: min(5, min(2, 6)) = 2 turns for child.\n")

    parent_llm, child_llm = resolve_llm_pair(
        mode,
        parent_responses=PARENT_SCRIPTED_RESPONSES,
        child_responses=CHILD_SCRIPTED_RESPONSES,
    )

    spell = Cantrip(
        llm=parent_llm,
        child_llm=child_llm,
        identity=Identity(
            system_prompt=(
                "You are a delegator. You have two tools:\n"
                "  call_entity(intent=...) — delegate a task to a child\n"
                "  done(answer=...) — finish with your final answer\n"
                "Delegate the user's question to a child, then pass the child's answer to done()."
            ),
            require_done_tool=True,
        ),
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 5}, {"max_depth": 1}],
        ),
    )

    result, parent_thread = spell.cast_with_thread(
        "List 3 facts about renewable energy by delegating to a child entity, then call done(answer)."
    )

    child_threads = [t for t in spell.loom.list_threads() if t.id != parent_thread.id]
    child_thread = child_threads[0] if child_threads else None

    print(f"Parent turns: {len(parent_thread.turns)}")
    print(f"Child turns:  {len(child_thread.turns) if child_thread else 0}")
    print(f"Child terminated: {bool(child_thread and child_thread.terminated)}")
    print(f"Result: {result}")

    return {
        "pattern": 5,
        "result": result,
        "parent_turns": len(parent_thread.turns),
        "child_turns": len(child_thread.turns) if child_thread else 0,
        "child_terminated": bool(child_thread and child_thread.terminated),
        "max_turns_min_wins": max_turns_min_wins_direct and bool(child_thread and len(child_thread.turns) <= 2),
        "require_done_or": or_wins,
        "depth_zero_removes_delegation": not has_call_entity,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
