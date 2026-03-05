from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from cantrip import Cantrip, Circle, FakeLLM, Identity, OpenAICompatLLM
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "repo_read", "args": {"path": "missing.txt"}}]},
    {"tool_calls": [{"gate": "repo_read", "args": {"path": "metrics.txt"}}]},
    {"tool_calls": [{"gate": "done", "args": {"answer": "Recovered after read error; metrics reviewed."}}]},
]


def _resolve_llm(mode: str | None = None) -> LLM:
    if mode == "scripted":
        return FakeLLM({"responses": SCRIPTED_RESPONSES})
    load_dotenv_if_present(str(Path(__file__).resolve().parents[2] / ".env"))
    model = os.environ.get("OPENAI_MODEL") or os.environ.get("CANTRIP_OPENAI_MODEL")
    base_url = os.environ.get("OPENAI_BASE_URL", os.environ.get("CANTRIP_OPENAI_BASE_URL", "https://api.openai.com/v1"))
    api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get("CANTRIP_OPENAI_API_KEY")
    if not model:
        raise RuntimeError("Missing OPENAI_MODEL (or CANTRIP_OPENAI_MODEL). Set it in .env or environment.")
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY (or CANTRIP_OPENAI_API_KEY). Set it in .env or environment.")
    return OpenAICompatLLM(model=model, base_url=base_url, api_key=api_key)


def run(mode: str | None = None) -> dict[str, Any]:
    # Pattern 7: code medium + filesystem gate + adaptation after error.
    workspace = Path(tempfile.mkdtemp(prefix="cantrip-full-agent-"))
    (workspace / "metrics.txt").write_text(
        "Q1 revenue +14%\nQ1 support cost +1%\nQ1 churn -2 pts\n", encoding="utf-8"
    )

    spell = Cantrip(
        llm=_resolve_llm(mode),
        identity=Identity(
            system_prompt=(
                "You are a file analyst. You have two tools: repo_read(path) to read files, "
                "and done(answer) to finish. If a read fails, you'll get an error — try a different path. "
                "Call done(answer) with your findings when ready."
            ),
            require_done_tool=True,
        ),
        circle=Circle(
            gates=["done", {"name": "repo_read", "depends": {"root": str(workspace)}}],
            wards=[{"max_turns": 5}],
        ),
    )

    result, thread = spell.cast_with_thread(
        "First try to read missing.txt with repo_read. It will fail. Then read metrics.txt instead. Then call done with the contents."
    )
    observations = [rec for turn in thread.turns for rec in turn.observation]
    errors = [o for o in observations if o.is_error]
    successes = [o for o in observations if not o.is_error and o.gate_name == "repo_read"]

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
