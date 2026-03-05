from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "repo_read", "args": {"path": "missing.txt"}}]},
    {"tool_calls": [{"gate": "repo_read", "args": {"path": "metrics.txt"}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Recovered after read error; metrics reviewed."}}]},
]


def _resolve_llm(llm: LLM | None) -> LLM:
    if llm is not None:
        return llm
    try:
        return OpenAICompatLLM(
            model=os.environ["CANTRIP_OPENAI_MODEL"],
            base_url=os.environ["CANTRIP_OPENAI_BASE_URL"],
            api_key=os.getenv("CANTRIP_OPENAI_API_KEY"),
        )
    except Exception:
        return FakeLLM({"responses": SCRIPTED_RESPONSES})


def run(llm: LLM | None = None) -> dict[str, Any]:
    # Pattern 7: code medium + filesystem gate + adaptation after error.
    workspace = Path(tempfile.mkdtemp(prefix="cantrip-full-agent-"))
    (workspace / "metrics.txt").write_text(
        "Q1 revenue +14%\nQ1 support cost +1%\nQ1 churn -2 pts\n", encoding="utf-8"
    )

    spell = Cantrip(
        llm=_resolve_llm(llm),
        identity=Identity(
            system_prompt=(
                "Act like a coding agent. Read files, adapt on failures, then done(answer)."
            ),
            require_done_tool=True,
        ),
        circle=Circle(
            medium="code",
            gates=["done", {"name": "repo_read", "depends": {"root": str(workspace)}}],
            wards=[{"max_turns": 5}],
        ),
    )

    result, thread = spell.cast_with_thread(
        "Analyze the workspace metrics file and summarize the trend."
    )
    observations = [rec for turn in thread.turns for rec in turn.observation]

    return {
        "pattern": 7,
        "result": result,
        "turn_count": len(thread.turns),
        "terminated": thread.terminated,
        "first_error": observations[0].is_error if observations else False,
        "error_message": observations[0].content if observations else "",
        "adapted_with_second_read": len(observations) >= 2 and not observations[1].is_error,
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
