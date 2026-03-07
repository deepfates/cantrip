"""Pattern 10: Loom — inspect after run, terminated vs truncated, token counts.

The loom records every turn as immutable history. Two casts into the same loom
show the two ways a thread can end: terminated (entity called done) or
truncated (hit max_turns ward before finishing).
Medium: tool | LLM: Yes | Recursion: No
"""
from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, Identity, InMemoryLoomStore, Loom

from ._llm import resolve_llm

# Cast 1: entity calls done immediately → terminated (LOOM-3).
TERMINATED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [{"gate": "done", "args": {"answer": "Revenue grew 15% YoY to $4.2M driven by enterprise SaaS deals."}}],
        "usage": {"prompt_tokens": 11, "completion_tokens": 7},
    },
]

# Cast 2: entity echoes observations but never calls done → truncated at max_turns (LOOM-7).
TRUNCATED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [{"gate": "echo", "args": {"text": "Q1: Revenue $4.2M, OpEx $3.8M, margin 9.5%"}}],
        "usage": {"prompt_tokens": 5, "completion_tokens": 3},
    },
    {
        "tool_calls": [{"gate": "echo", "args": {"text": "Q2 pipeline: $12M, two enterprise deals pending"}}],
        "usage": {"prompt_tokens": 5, "completion_tokens": 3},
    },
    {
        "tool_calls": [{"gate": "echo", "args": {"text": "Headcount: 47 (+5), infra costs down 12%"}}],
        "usage": {"prompt_tokens": 5, "completion_tokens": 3},
    },
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 10: loom inspection — the most useful artifact (LOOM-3, LOOM-7)."""
    # LOOM-1: A single loom can hold multiple threads from different casts.
    loom = Loom(store=InMemoryLoomStore())
    is_scripted = mode == "scripted"

    # Ensure env vars are checked in real mode (no silent fallback).
    if not is_scripted:
        resolve_llm(mode)

    print("=== Pattern 10: Loom ===")
    print("The loom records every turn as immutable history.")
    print("Two casts into the same loom show terminated vs truncated threads.\n")

    # ── Cast 1: entity terminates by calling done ──────────────────────────
    terminated_llm = resolve_llm("scripted", TERMINATED_RESPONSES) if is_scripted else resolve_llm(mode)
    terminated_spell = Cantrip(
        llm=terminated_llm,
        identity=Identity(
            system_prompt="You are a financial analyst. Summarize the data, then call done(answer).",
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}, {"require_done_tool": True}]),
        loom=loom,
    )

    print("Cast 1: 'Summarize Q1 revenue performance'")
    print("  Gates: [done]  Wards: [max_turns=3]")
    terminated_result, terminated_thread = terminated_spell.cast_with_thread(
        "Summarize Q1 revenue performance: Revenue grew 15% YoY to $4.2M. SaaS ARR reached $3.1M."
    )
    print(f"  Result: {terminated_result}")
    print(f"  Terminated: {terminated_thread.terminated} (entity called done)")
    print(f"  Turns: {len(terminated_thread.turns)}")
    print(f"  Tokens: {terminated_thread.cumulative_usage['total_tokens']}")

    # ── Cast 2: entity truncated by max_turns ward ─────────────────────────
    truncated_llm = resolve_llm("scripted", TRUNCATED_RESPONSES) if is_scripted else resolve_llm(mode)
    truncated_spell = Cantrip(
        llm=truncated_llm,
        identity=Identity(
            system_prompt=(
                "You have echo(text) and done(answer). "
                "Use echo to record each observation. Only call done when analysis is complete."
            ),
        ),
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 3}, {"require_done_tool": True}]),
        loom=loom,
    )

    print("\nCast 2: 'Analyze all quarterly metrics in detail'")
    print("  Gates: [done, echo]  Wards: [max_turns=3]")
    truncated_result, truncated_thread = truncated_spell.cast_with_thread(
        "Analyze all quarterly metrics in detail, echoing each finding: "
        "Q1 Revenue $4.2M, OpEx $3.8M, pipeline $12M, headcount 47."
    )
    print(f"  Result: {truncated_result}")
    print(f"  Truncated: {truncated_thread.truncated} (hit max_turns before calling done)")
    print(f"  Turns: {len(truncated_thread.turns)}")
    print(f"  Tokens: {truncated_thread.cumulative_usage['total_tokens']}")

    # ── Loom inspection ────────────────────────────────────────────────────
    threads = loom.list_threads()
    total_turns = len(loom.turns)

    print(f"\n--- Loom Summary ---")
    print(f"  Threads: {len(threads)}")
    print(f"  Total turns: {total_turns}")
    print(f"  Thread 1 (terminated): {terminated_thread.id}")
    print(f"  Thread 2 (truncated):  {truncated_thread.id}")
    print(f"  Token counts: [{terminated_thread.cumulative_usage['total_tokens']}, "
          f"{truncated_thread.cumulative_usage['total_tokens']}]")
    print("\nThe loom is the audit trail. Every turn is recorded, whether the entity")
    print("finished gracefully (terminated) or was cut short by a ward (truncated).")

    return {
        "pattern": 10,
        "results": [terminated_result, truncated_result],
        "thread_count": len(threads),
        "turn_count": total_turns,
        "terminated": terminated_thread.terminated,
        "truncated": truncated_thread.truncated,
        "total_tokens": [
            terminated_thread.cumulative_usage["total_tokens"],
            truncated_thread.cumulative_usage["total_tokens"],
        ],
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
