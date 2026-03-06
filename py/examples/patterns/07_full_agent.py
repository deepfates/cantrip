from __future__ import annotations

import json
import tempfile
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, Identity

from ._llm import resolve_llm

# Scripted responses simulate: bad path → error → correct path → done.
# This is the error-steering pattern (SPEC A.7): the agent adapts when a gate
# returns an error observation, without any human intervention.
SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "repo_read", "args": {"path": "missing.txt"}}]},
    {"tool_calls": [{"gate": "repo_read", "args": {"path": "metrics.txt"}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Recovered after read error; metrics reviewed."}}]},
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 7: Full Agent — code medium + filesystem gate + error recovery.

    The agent tries to read a file that doesn't exist, gets an error observation,
    then adapts by reading a different file. This demonstrates error steering:
    the circle doesn't crash on gate errors; it feeds them back as observations
    and the entity decides what to do next (CIRCLE-3, GATE-2).
    """
    print("=== Pattern 07: Full Agent (Error Steering) ===")
    print("An agent with repo_read and done gates. It will hit an error and recover.")
    print()

    # Set up a workspace with one real file. The agent will first try a
    # nonexistent file and get an error, then find the real one.
    workspace = Path(tempfile.mkdtemp(prefix="cantrip-full-agent-"))
    metrics_content = "Q1 revenue +14%\nQ1 support cost +1%\nQ1 churn -2 pts\n"
    (workspace / "metrics.txt").write_text(metrics_content, encoding="utf-8")
    print(f"Workspace: {workspace}")
    print(f"  metrics.txt exists: True")
    print(f"  missing.txt exists: False")
    print()

    # Visible construction: identity, circle, gates, wards — all inline (CANTRIP-1).
    spell = Cantrip(
        llm=resolve_llm(mode, scripted_responses=SCRIPTED_RESPONSES),
        identity=Identity(
            system_prompt=(
                "You are a file analyst. You have two tools: repo_read(path) to read files, "
                "and done(answer) to finish. If a read fails, you'll get an error — try a different path. "
                "Call done(answer) with your findings when ready."
            ),
            require_done_tool=True,  # WARD: agent must call done() to terminate
        ),
        circle=Circle(
            gates=["done", {"name": "repo_read", "depends": {"root": str(workspace)}}],
            wards=[{"max_turns": 5}],  # WARD-1: safety bound on loop iterations
        ),
    )

    print("Cast: 'Read missing.txt, then recover and read metrics.txt.'")
    result, thread = spell.cast_with_thread(
        "First try to read missing.txt with repo_read. It will fail. "
        "Then read metrics.txt instead. Then call done with the contents."
    )

    # Inspect the thread to verify error steering happened.
    observations = [rec for turn in thread.turns for rec in turn.observation]
    errors = [o for o in observations if o.is_error]
    successes = [o for o in observations if not o.is_error and o.gate_name == "repo_read"]

    # Narrate what happened turn by turn.
    for i, turn in enumerate(thread.turns, 1):
        calls = [r.gate_name for r in turn.observation]
        errs = [r.gate_name for r in turn.observation if r.is_error]
        print(f"  Turn {i}: called {calls}" + (f" — errors: {errs}" if errs else ""))

    print()
    print(f"Result: {result}")
    print(f"Terminated cleanly: {thread.terminated}")
    print(f"Errors encountered: {len(errors)}")
    print(f"Successful reads: {len(successes)}")
    if errors:
        print(f"  Error steering: agent hit an error on '{errors[0].gate_name}', then recovered.")
    print()

    return {
        "pattern": 7,
        "result": result,
        "turn_count": len(thread.turns),
        "terminated": thread.terminated,
        "had_error": len(errors) > 0,
        "error_then_recovery": len(errors) > 0 and len(successes) > 0,
        "successful_read": successes[0].result if successes else None,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
