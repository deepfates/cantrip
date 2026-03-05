from __future__ import annotations

import json
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity

# Folding is a structural feature — it compresses older turns to keep context small.
# Demonstrated with FakeLLM + record_inputs regardless of mode, because the point
# is to observe folding markers in the context window, not LLM behavior.

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-1"}}]},
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-2"}}]},
    {"tool_calls": [{"gate": "echo", "args": {"text": "turn-3"}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Folded and finished."}}]},
]


def run(mode: str | None = None) -> dict[str, Any]:
    # Pattern 8: long threads trigger folding of old context (FOLD-1).
    # Folding is structural — always uses FakeLLM with record_inputs to inspect context.
    active_llm = FakeLLM({"responses": SCRIPTED_RESPONSES, "record_inputs": True})
    spell = Cantrip(
        llm=active_llm,
        identity=Identity(
            system_prompt=(
                "You have echo(text) for notes and done(answer) to finish. "
                "Use echo for intermediate observations, then done when complete."
            )
        ),
        circle=Circle(gates=["done", "echo"], wards=[{"max_turns": 8}]),
        folding={"trigger_after_turns": 2},
    )

    result, thread = spell.cast_with_thread(
        "Count to three, echoing each number with echo(text), then call done('counting complete')."
    )

    folded_seen = False
    identity_preserved = False
    invocations = getattr(active_llm, "invocations", [])
    for call in invocations:
        messages = call.get("messages", [])
        if any(msg.get("content") == "[folded context]" for msg in messages):
            folded_seen = True
        if messages and messages[0].get("role") == "system":
            identity_preserved = True

    return {
        "pattern": 8,
        "result": result,
        "turn_count": len(thread.turns),
        "folded_context_seen": folded_seen,
        "identity_preserved": identity_preserved,
        "loom_turns": len(spell.loom.turns),
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
