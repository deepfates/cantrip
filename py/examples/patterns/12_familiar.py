from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from cantrip import (
    Cantrip,
    Circle,
    Entity,
    FakeLLM,
    Identity,
    Loom,
    OpenAICompatLLM,
    SQLiteLoomStore,
)
from cantrip.env import load_dotenv_if_present
from cantrip.providers.base import LLM

# Simplified code medium delegation: children inherit parent's medium (code).
# No need to specify llm/medium in call_entity args.
SCRIPTED_RESPONSES: list[dict[str, Any]] = [
    {
        "tool_calls": [{
            "gate": "code",
            "args": {
                "code": (
                    'a = call_entity({"intent": "Compute 2+3 and call done(answer)"})\n'
                    'b = call_entity({"intent": "What is the capital of Japan? Call done(answer)"})\n'
                    "done(str(a) + ' | ' + str(b))"
                )
            },
        }]
    },
    {
        "tool_calls": [{
            "gate": "code",
            "args": {
                "code": (
                    'a = call_entity({"intent": "Compute 10*5 and call done(answer)"})\n'
                    'b = call_entity({"intent": "What is the capital of Germany? Call done(answer)"})\n'
                    "done(str(a) + ' | ' + str(b))"
                )
            },
        }]
    },
]

# Children also use code medium (inherited), so they respond with code tool calls.
CHILD_RESPONSES: list[dict[str, Any]] = [
    {"tool_calls": [{"gate": "code", "args": {"code": "done('5')"}}]},
    {"tool_calls": [{"gate": "code", "args": {"code": "done('Tokyo')"}}]},
    {"tool_calls": [{"gate": "code", "args": {"code": "done('50')"}}]},
    {"tool_calls": [{"gate": "code", "args": {"code": "done('Berlin')"}}]},
]


def _resolve_llm(mode: str | None = None) -> tuple[LLM, bool]:
    if mode == "scripted":
        return FakeLLM({"responses": SCRIPTED_RESPONSES}), False
    load_dotenv_if_present(str(Path(__file__).resolve().parents[2] / ".env"))
    model = os.environ.get("OPENAI_MODEL") or os.environ.get("CANTRIP_OPENAI_MODEL")
    base_url = os.environ.get("OPENAI_BASE_URL", os.environ.get("CANTRIP_OPENAI_BASE_URL", "https://api.openai.com/v1"))
    api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get("CANTRIP_OPENAI_API_KEY")
    if not model:
        raise RuntimeError("Missing OPENAI_MODEL (or CANTRIP_OPENAI_MODEL). Set it in .env or environment.")
    if not api_key:
        raise RuntimeError("Missing OPENAI_API_KEY (or CANTRIP_OPENAI_API_KEY). Set it in .env or environment.")
    return OpenAICompatLLM(model=model, base_url=base_url, api_key=api_key), True


def run(mode: str | None = None) -> dict[str, Any]:
    # Pattern 12: familiar coordinates child cantrips and keeps a persistent loom (FAM-1).
    parent_llm, using_real = _resolve_llm(mode)

    if using_real:
        child_llm: LLM = parent_llm
    else:
        child_llm = FakeLLM({"responses": CHILD_RESPONSES})

    loom_path = Path(tempfile.mkdtemp(prefix="cantrip-familiar-")) / "loom.db"
    loom = Loom(store=SQLiteLoomStore(loom_path))

    familiar_spell = Cantrip(
        llm=parent_llm,
        child_llm=child_llm,
        circle=Circle(
            medium="code",
            gates=["done", "call_entity"],
            wards=[{"max_turns": 6}, {"max_depth": 2}],
        ),
        medium_depends={"code": {"timeout_s": 60}},
        identity=Identity(
            system_prompt=(
                "You are a coordinator that delegates tasks to child entities.\n"
                "Use the code tool to write Python. Available functions:\n"
                "  done(answer)  -- finish and return your final answer\n"
                "  call_entity(config_dict)  -- delegate a task to a child entity\n"
                "Each call_entity takes a dict with an 'intent' key describing what the child should do.\n"
                "The child will return its result as a string.\n"
                "After all children return, combine results and call done().\n"
                "Example:\n"
                '  result1 = call_entity({"intent": "What is 2+2?"})\n'
                '  result2 = call_entity({"intent": "Name the largest planet"})\n'
                "  done(result1 + ' | ' + result2)\n"
                "IMPORTANT: Replace the example intents with the ACTUAL tasks from the user's request."
            ),
            require_done_tool=True,
        ),
        loom=loom,
    )

    familiar: Entity = familiar_spell.summon()
    first = familiar.send(
        "Delegate two tasks to child entities: one to compute 2+3 "
        "and one to find the capital of Japan. Combine results with done()."
    )
    second = familiar.send(
        "Delegate two more tasks: compute 10*5 "
        "and find the capital of Germany. Combine results with done()."
    )

    thread_ids = [t.id for t in loom.list_threads()]
    reloaded = Loom(store=SQLiteLoomStore(loom_path))
    persisted_any = bool(thread_ids and reloaded.get_thread(thread_ids[0]) is not None)

    return {
        "pattern": 12,
        "first": first,
        "second": second,
        "loom_threads": len(loom.list_threads()),
        "entity_turns": len(familiar.turns),
        "persisted_loom": persisted_any,
        "child_code_calls": len(getattr(child_llm, "invocations", [])),
        "child_tool_calls": 0,  # No tool-medium children in simplified version
    }


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
