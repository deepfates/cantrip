"""Pattern 12: The Familiar — persistent coordinator that delegates via code medium.

The capstone pattern. A long-running entity with:
  - Code medium: thinks in Python, calls gates as functions (MEDIUM-1)
  - call_entity gate: delegates tasks to child entities (COMPOSE-1)
  - Persistent SQLite loom: remembers across sessions (LOOM-1)
  - Two sends: first gathers information, second builds on it (ENTITY-1)

The familiar doesn't do leaf work itself. It writes code that delegates to
children via call_entity, combines their results, and calls done().
"""
from __future__ import annotations

import json
import tempfile
from pathlib import Path
from typing import Any

from cantrip import (
    Cantrip,
    Circle,
    Identity,
    Loom,
    SQLiteLoomStore,
)

from ._llm import resolve_llm_pair

# --- Scripted responses for the parent (coordinator) ---
# Send 1: parent writes code that delegates a research task to a child,
#          then delegates a second task, and combines results.
# Send 2: parent builds on send 1, delegating a synthesis task.
PARENT_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [
            {
                "gate": "code",
                "args": {
                    "code": (
                        "# Delegate two research tasks to children (COMPOSE-1)\n"
                        'trends = call_entity({"intent": "Identify the top 3 trends in this Q3 data: '
                        "Revenue $4.2M (+14% QoQ), churn 4.0% (was 6.1%), "
                        'net new ARR $580K, CAC payback 11mo. Call done(answer)."})\n'
                        'risks = call_entity({"intent": "What are the 2 biggest risks given: '
                        "churn improved but still 4%, CAC payback 11mo, "
                        'heavy reliance on single channel. Call done(answer)."})\n'
                        "done('TRENDS: ' + str(trends) + ' | RISKS: ' + str(risks))"
                    )
                },
            }
        ]
    },
    {
        "tool_calls": [
            {
                "gate": "code",
                "args": {
                    "code": (
                        "# Build on prior analysis — synthesize a recommendation (ENTITY-1)\n"
                        'plan = call_entity({"intent": "Given these findings — revenue +14%, churn dropping, '
                        "CAC payback 11mo — draft a 2-sentence action plan for Q4. "
                        'Call done(answer)."})\n'
                        "done('Q4 ACTION PLAN: ' + str(plan))"
                    )
                },
            }
        ]
    },
]

# --- Scripted responses for children ---
# Children use code medium (inherited from parent), so they respond with code calls.
CHILD_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [
            {
                "gate": "code",
                "args": {
                    "code": "done('1) Revenue acceleration (+14% QoQ), 2) Churn improvement (6.1->4.0%), 3) Efficient growth (11mo CAC payback)')"
                },
            }
        ]
    },
    {
        "tool_calls": [
            {
                "gate": "code",
                "args": {
                    "code": "done('1) Channel concentration risk — single acquisition channel, 2) Churn floor uncertainty — 4% may be structural')"
                },
            }
        ]
    },
    {
        "tool_calls": [
            {
                "gate": "code",
                "args": {
                    "code": "done('Increase acquisition spend 30% on the proven channel while investing 15% of marketing budget in a second channel to reduce concentration risk.')"
                },
            }
        ]
    },
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 12: familiar — persistent coordinator with code medium (FAM-1)."""

    parent_llm, child_llm = resolve_llm_pair(
        mode,
        parent_responses=PARENT_RESPONSES,
        child_responses=CHILD_RESPONSES,
    )

    # -- Persistent loom: SQLite on disk survives across runs (LOOM-1) --
    loom_path = Path(tempfile.mkdtemp(prefix="cantrip-familiar-")) / "loom.db"
    loom = Loom(store=SQLiteLoomStore(loom_path))

    print("=== Pattern 12: The Familiar ===")
    print("A persistent coordinator that delegates to children via code medium.\n")
    print(f"Loom path: {loom_path}")

    # -- Construct the familiar's cantrip --
    # Code medium + call_entity gate + done gate (MEDIUM-1, COMPOSE-1)
    # Wards: max_turns=6 prevents runaway, max_depth=2 limits child nesting (WARD-1)
    familiar_spell = Cantrip(
        llm=parent_llm,
        child_llm=child_llm,
        circle=Circle(
            medium="code",
            gates=["done", "call_entity"],
            wards=[{"max_turns": 6}, {"max_depth": 2}, {"require_done_tool": True}],
        ),
        medium_depends={"code": {"timeout_s": 120}},
        identity=Identity(
            system_prompt=(
                "You are a coordinator. You delegate work to children and combine results.\n\n"
                "ONLY these functions exist:\n"
                '  result = call_entity({"intent": "task description"})  # returns child answer as string\n'
                "  done(answer)  # finish and return your combined answer\n\n"
                "RULES:\n"
                "- Do NOT define classes, helpers, or error handling. Just call_entity and done.\n"
                "- Each call_entity takes one dict with 'intent' key. Keep intents short and specific.\n"
                "- Combine results with simple string concatenation or formatting.\n"
                "- You MUST call done() in every response. No exceptions.\n\n"
                "Example (complete response):\n"
                '  trends = call_entity({"intent": "List top 3 Q3 revenue trends"})\n'
                '  risks = call_entity({"intent": "List top 2 risks from Q3 data"})\n'
                "  done(f'Trends: {trends}\\nRisks: {risks}')"
            ),
        ),
        loom=loom,
    )

    # -- Summon: creates a persistent familiar entity (ENTITY-1) --
    familiar = familiar_spell.summon()

    # -- Send 1: research phase — delegate trend + risk analysis to children --
    print("\n[Send 1] Research phase: delegate trend and risk analysis")
    first = familiar.send(
        "Analyze our Q3 SaaS metrics: Revenue $4.2M (+14% QoQ), churn 4.0% "
        "(was 6.1%), net new ARR $580K, CAC payback 11 months. "
        "Identify key trends and risks by delegating to specialist children."
    )
    print(f"  Result: {first}\n")

    # -- Send 2: synthesis phase — builds on the research from send 1 --
    print("[Send 2] Synthesis phase: draft Q4 action plan based on prior analysis")
    second = familiar.send(
        "Based on the trends and risks from your prior analysis, "
        "draft an action plan for Q4. Delegate the drafting to a child."
    )
    print(f"  Result: {second}\n")

    # -- Inspect the loom: threads from parent + children --
    thread_ids = [t.id for t in loom.list_threads()]
    print(f"Loom threads: {len(thread_ids)} (parent + child threads)")
    print(f"Entity accumulated turns: {len(familiar.turns)}")

    # -- Verify persistence: reload from the same SQLite file --
    reloaded = Loom(store=SQLiteLoomStore(loom_path))
    persisted = bool(thread_ids and reloaded.get_thread(thread_ids[0]) is not None)
    print(f"Loom persisted to disk: {persisted}")

    print("\nThe familiar delegates work through code, not tools.")
    print("Children do the leaf work. The loom records everything (LOOM-1).")

    return {
        "pattern": 12,
        "first": first,
        "second": second,
        "loom_threads": len(thread_ids),
        "entity_turns": len(familiar.turns),
        "persisted_loom": persisted,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
