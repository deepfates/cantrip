"""Pattern 09: Composition — batch delegation via call_entity_batch.

A parent entity splits financial document analysis across child entities
that run in parallel. Each child gets independent context and a fresh circle.
Medium: code | LLM: Yes | Recursion: Yes (depth 1)
"""
from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, Identity

from ._llm import resolve_llm_pair

# Financial documents for analysis — three documents, each handled by a focused child.
DOCUMENTS = [
    {"id": 1, "title": "Q1 Revenue", "content": "Revenue grew 15% YoY to $4.2M. SaaS ARR reached $3.1M. Enterprise deals drove 60% of new bookings."},
    {"id": 2, "title": "Q1 Costs", "content": "Total OpEx was $3.8M, up 8%. Headcount grew from 42 to 47. Infrastructure costs fell 12% after migration."},
    {"id": 3, "title": "Q1 Outlook", "content": "Pipeline is $12M, up 25%. Two enterprise deals expected to close in Q2. Hiring plan: 5 engineers, 2 sales."},
]

# Parent uses code medium: writes Python that calls call_entity_batch() (COMP-3).
# Children inherit code medium, analyze one document each, and call done().
PARENT_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [{
            "gate": "code",
            "args": {
                "code": (
                    "results = call_entity_batch([\n"
                    '  {"intent": "Summarize the Q1 Revenue document: Revenue grew 15% YoY to $4.2M. SaaS ARR reached $3.1M. Enterprise deals drove 60% of new bookings."},\n'
                    '  {"intent": "Summarize the Q1 Costs document: Total OpEx was $3.8M, up 8%. Headcount grew from 42 to 47. Infrastructure costs fell 12% after migration."},\n'
                    '  {"intent": "Summarize the Q1 Outlook document: Pipeline is $12M, up 25%. Two enterprise deals expected to close in Q2. Hiring plan: 5 engineers, 2 sales."}\n'
                    "])\n"
                    "done('Financial Summary:\\n' + '\\n'.join(str(r) for r in results))"
                )
            },
        }]
    },
]

CHILD_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "code", "args": {"code": "done('Revenue: 15% YoY growth to $4.2M, SaaS ARR $3.1M, enterprise-led bookings.')"}}]},
    {"tool_calls": [{"gate": "code", "args": {"code": "done('Costs: OpEx $3.8M (+8%), 5 new hires, infra costs down 12% post-migration.')"}}]},
    {"tool_calls": [{"gate": "code", "args": {"code": "done('Outlook: $12M pipeline (+25%), 2 enterprise deals near close, 7 hires planned.')"}}]},
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 9: parent delegates via call_entity_batch in code medium (COMP-3)."""
    parent_llm, child_llm = resolve_llm_pair(
        mode,
        parent_responses=PARENT_RESPONSES,
        child_responses=CHILD_RESPONSES,
    )

    print("=== Pattern 09: Composition ===")
    print("A parent entity delegates document analysis to children via call_entity_batch.")
    print("Children run in parallel, each with independent context and a fresh circle.\n")

    print("Documents to analyze:")
    for doc in DOCUMENTS:
        print(f"  [{doc['id']}] {doc['title']}: {doc['content'][:60]}...")
    print()

    # COMP-1: Parent circle includes call_entity_batch gate for delegation.
    # COMP-2: max_depth ward limits recursion depth.
    spell = Cantrip(
        llm=parent_llm,
        child_llm=child_llm,
        identity=Identity(
            system_prompt=(
                "You are a financial analyst coordinator. Use the code tool to write Python.\n"
                "Available functions:\n"
                "  call_entity_batch(list_of_dicts) -- delegate tasks to children in parallel\n"
                "  done(answer) -- finish with your final answer\n"
                "Each dict needs an 'intent' key describing what the child should analyze.\n"
                "Children will return string summaries.\n"
                "Combine their results and call done() with the synthesis."
            ),
            require_done_tool=True,
        ),
        circle=Circle(
            medium="code",
            gates=["done", "call_entity", "call_entity_batch"],
            wards=[{"max_turns": 6}, {"max_depth": 1}],
        ),
        medium_depends={"code": {"timeout_s": 60}},
    )

    print("Parent delegates: call_entity_batch with 3 document summaries...")
    result, parent_thread = spell.cast_with_thread(
        "Analyze these financial documents by delegating each to a child entity via "
        "call_entity_batch, then synthesize an overall summary:\n"
        + "\n".join(f"- {doc['title']}: {doc['content']}" for doc in DOCUMENTS)
    )

    # Inspect the loom tree: parent + child threads (LOOM-5).
    all_threads = spell.loom.list_threads()
    child_threads = [t for t in all_threads if t.id != parent_thread.id]
    batch_record = parent_thread.turns[0].observation[0] if parent_thread.turns else None

    print(f"\nParent answer: {result}")
    print(f"\nLoom tree:")
    print(f"  Parent thread: {parent_thread.id} ({len(parent_thread.turns)} turns)")
    for ct in child_threads:
        print(f"  Child thread:  {ct.id} ({len(ct.turns)} turns)")
    print(f"\n  Total threads: {len(all_threads)} (1 parent + {len(child_threads)} children)")
    if batch_record and isinstance(getattr(batch_record, 'result', None), list):
        print(f"  Batch results: {len(batch_record.result)} documents summarized")

    return {
        "pattern": 9,
        "result": result,
        "parent_turns": len(parent_thread.turns),
        "child_threads": len(child_threads),
        "child_thread_ids": [t.id for t in child_threads],
        "batch_result_count": len(batch_record.result) if batch_record and isinstance(getattr(batch_record, 'result', None), list) else 0,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
