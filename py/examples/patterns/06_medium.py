"""Pattern 06: Medium — same gates, different action space.

The formula A = M U G - W becomes concrete here.
Same gates (done), same wards, but tool medium vs code medium
produce different tool surfaces for the LLM.

Tool medium: LLM sees done() as a JSON tool call.
Code medium: LLM writes Python code; done() is a callable in the sandbox.
"""
from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, Identity
from cantrip.mediums import medium_for

from ._llm import resolve_llm

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "done", "args": {"answer": "tool medium answer"}}]},
    {"code": "done('code medium answer')"},
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 6: same gates, different medium, different action space."""

    print("=== Pattern 06: Medium ===")
    print("A = M U G - W  — the formula becomes concrete.")
    print("Same gates, same wards, but different mediums produce different surfaces.\n")

    active_llm = resolve_llm(mode, scripted_responses=SCRIPTED_RESPONSES)

    # ── Tool medium: G = {done}, M = tool (JSON tool calls) ──────────────
    tool_circle = Circle(gates=["done"], wards=[{"max_turns": 4}], medium="tool")
    tool_cantrip = Cantrip(
        llm=active_llm,
        circle=tool_circle,
        identity=Identity(system_prompt="You have one tool: done(answer). Call done(answer) with your response."),
    )

    # ── Code medium: G = {done}, M = code (Python sandbox) ──────────────
    code_circle = Circle(gates=["done"], wards=[{"max_turns": 4}], medium="code")
    code_cantrip = Cantrip(
        llm=active_llm,
        circle=code_circle,
        identity=Identity(
            system_prompt=(
                "You write Python code using the 'code' tool. "
                "Available function: done(answer). Call done('your answer') to finish. "
                "Variables persist across turns. Example: done('56')"
            ),
            require_done_tool=True,
        ),
    )

    # Show the tool surfaces BEFORE running — this is the action space.
    tool_surface = [t["name"] for t in medium_for("tool").make_tools(tool_circle)]
    code_surface = [t["name"] for t in medium_for("code").make_tools(code_circle)]

    print("Tool medium surface (what the LLM sees as JSON tools):")
    for name in tool_surface:
        print(f"  - {name}")
    print(f"\nCode medium surface (what the LLM sees as callable tools):")
    for name in code_surface:
        print(f"  - {name}")
    print()

    print("Same gate (done), but tool medium exposes it as a JSON schema,")
    print("while code medium wraps it in a Python sandbox with a 'code' tool.\n")

    # ── Run both ─────────────────────────────────────────────────────────
    tool_result, tool_thread = tool_cantrip.cast_with_thread(
        "What is the capital of France? Call done(answer) with your response."
    )
    code_result, code_thread = code_cantrip.cast_with_thread(
        "Compute 7 * 8 and return the result by calling done() with the answer."
    )

    print(f"Tool medium result: {tool_result}")
    print(f"Code medium result: {code_result}")
    print(f"Tool medium turns:  {len(tool_thread.turns)}")
    print(f"Code medium turns:  {len(code_thread.turns)}")

    return {
        "pattern": 6,
        "tool_result": tool_result,
        "code_result": code_result,
        "tool_surface": tool_surface,
        "code_surface": code_surface,
        "code_observation_gates": [rec.gate_name for rec in code_thread.turns[0].observation],
        "turn_counts": [len(tool_thread.turns), len(code_thread.turns)],
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
