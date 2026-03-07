"""Pattern 07: Codex — code medium + filesystem gate + error steering.

The entity writes Python code in a sandboxed exec() environment. Gates like
repo_read and done are available as host functions. When repo_read hits a
missing file, the error observation steers the entity to adapt — no crash,
no human intervention.

Spec ref: A.7 (Codex), CIRCLE-3 (error observations steer the entity),
          GATE-2 (gate errors are observations, not crashes).
"""
from __future__ import annotations

import json
import tempfile
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, Identity

from ._llm import resolve_llm

# Scripted responses simulate code medium: entity writes Python code.
# Turn 1: try to read a nonexistent file → error observation
# Turn 2: read the real file → success observation
# Turn 3: call done with findings
SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"code": 'result = call_gate("repo_read", {"path": "missing.txt"})'},
    {"code": 'result = call_gate("repo_read", {"path": "metrics.txt"})'},
    {"code": "done('Recovered after read error. Metrics: revenue +14%, churn -2 pts.')"},
]


def run(mode: str | None = None) -> dict[str, Any]:
    """Pattern 7: Codex — code medium + filesystem gate + error steering.

    The entity writes Python code that executes in a sandbox. Gates are
    host functions. When repo_read hits a missing file, the error feeds
    back as an observation and the entity adapts (CIRCLE-3, GATE-2).
    This is A.7: code medium with real gates.
    """
    print("=== Pattern 07: Codex (Code Medium + Error Steering) ===")
    print("A = M ∪ G − W where M = code (Python sandbox), G = {repo_read, done}.")
    print("The entity writes Python code; gates are host functions in the sandbox.")
    print()

    # Set up a workspace with one real file. The agent will first try a
    # nonexistent file and get an error, then find the real one.
    workspace = Path(tempfile.mkdtemp(prefix="cantrip-codex-"))
    metrics_content = "Q1 revenue +14%\nQ1 support cost +1%\nQ1 churn -2 pts\n"
    (workspace / "metrics.txt").write_text(metrics_content, encoding="utf-8")
    print(f"Workspace: {workspace}")
    print(f"  metrics.txt exists: True")
    print(f"  missing.txt exists: False")
    print()

    # Visible construction: code medium, real gates, wards — all inline (CANTRIP-1).
    spell = Cantrip(
        llm=resolve_llm(mode, scripted_responses=SCRIPTED_RESPONSES),
        identity=Identity(
            system_prompt=(
                "You write Python code to analyze files. "
                "Available host functions: call_gate('repo_read', {'path': '...'}) to read files, "
                "done(answer) to finish. If a read fails, adapt and try a different path."
            ),
            # require_done_tool is now a ward on the circle, not an identity property
        ),
        circle=Circle(
            gates=["done", {"name": "repo_read", "depends": {"root": str(workspace)}}],
            wards=[{"max_turns": 5}, {"require_done_tool": True}],  # WARD-1: safety bound on loop iterations
            medium="code",  # A.7: code medium — entity writes Python, not JSON tool calls
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
