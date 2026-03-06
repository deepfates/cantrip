"""Pattern 08: Folding — compress older turns to keep context small.

When a thread exceeds trigger_after_turns, early turns are replaced with
a '[folded context]' marker in the LLM's context window. The loom keeps
the full uncompressed history. The identity (system prompt) is always
preserved — folding never touches it.

Spec ref: FOLD-1 (folding compresses context), LOOM-2 (loom keeps full history).
"""
from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity

# Folding is a structural feature — it compresses older turns to keep the
# context window small when threads get long (SPEC A.8, FOLD-1).
#
# Key idea: the loom retains ALL turns (full history for replay/audit), but
# the context window sent to the LLM folds early turns into a summary marker.
# The entity's identity (system prompt) is NEVER folded — it stays at the top.
#
# This example always uses FakeLLM with record_inputs=True regardless of mode,
# because the point is to observe the folding mechanics, not LLM behavior.

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-1"}}]},
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-2"}}]},
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-3"}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Folded and finished."}}]},
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 8: Folding — compress older turns to keep context small.

    When a thread exceeds trigger_after_turns, early turns are replaced with
    a '[folded context]' marker in the LLM's context window. The loom keeps
    the full uncompressed history. The identity (system prompt) is always
    preserved — folding never touches it (FOLD-1, LOOM-2).
    """
    print("=== Pattern 08: Folding ===")
    print("When threads get long, folding compresses early turns into a summary.")
    print("The loom keeps full history; only the LLM's context window is compressed.")
    print()

    # FakeLLM with record_inputs=True lets us inspect what the LLM actually sees.
    active_llm = FakeLLM({"responses": SCRIPTED_RESPONSES, "record_inputs": True})

    # trigger_after_turns=2 means folding kicks in after 2 completed turns.
    # This is artificially low to demonstrate the mechanic in a short example.
    spell = Cantrip(
        llm=active_llm,
        identity=Identity(
            system_prompt=(
                "You have echo(text) for notes and done(answer) to finish. "
                "Use echo for intermediate observations, then done when complete."
            )
        ),
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 8}]),
        folding={"trigger_after_turns": 2},  # FOLD-1: fold after 2 turns
    )

    print("Cast: 'Count to three with echo, then done.'")
    print(f"  trigger_after_turns: 2 (folding kicks in early for demo)")
    print()

    result, thread = spell.cast_with_thread(
        "Count to three, echoing each number with echo(text), then call done('counting complete')."
    )

    # Inspect the recorded LLM invocations to verify folding behavior.
    folded_seen = False
    identity_preserved = False
    invocations = getattr(active_llm, "invocations", [])

    for i, call in enumerate(invocations):
        messages = call.get("messages", [])
        has_fold_marker = any(
            msg.get("content") == "[folded context]" for msg in messages
        )
        has_system = messages and messages[0].get("role") == "system"

        if has_fold_marker:
            folded_seen = True
        if has_system:
            identity_preserved = True

        # Show what the LLM saw on each invocation.
        msg_roles = [m.get("role", "?") for m in messages]
        marker = " [FOLDED]" if has_fold_marker else ""
        print(f"  LLM call {i + 1}: {len(messages)} messages ({', '.join(msg_roles)}){marker}")

    print()

    # The loom keeps everything — folding only affects the context window.
    loom_turn_count = len(spell.loom.turns)
    print(f"Thread turns: {len(thread.turns)} (what the loop produced)")
    print(f"Loom turns:   {loom_turn_count} (full history, never compressed)")
    print(f"Folded context seen in LLM input: {folded_seen}")
    print(f"Identity (system prompt) preserved: {identity_preserved}")
    print(f"Result: {result}")
    print()

    if folded_seen:
        print("Folding replaced early turns with '[folded context]' in the LLM's view,")
        print("but the loom still has all turns for replay or audit.")
    else:
        print("(Thread was too short to trigger folding in this run.)")
    print()

    return {
        "pattern": 8,
        "result": result,
        "turn_count": len(thread.turns),
        "folded_context_seen": folded_seen,
        "identity_preserved": identity_preserved,
        "loom_turns": loom_turn_count,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
