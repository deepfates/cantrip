from __future__ import annotations

import os
from pathlib import Path

from cantrip.env import load_dotenv_if_present
from cantrip.models import Call, Circle
from cantrip.providers.fake import FakeCrystal
from cantrip.providers.openai_compat import OpenAICompatCrystal
from cantrip.runtime import Cantrip


def _resolve_dotenv_path(repo_root: Path, dotenv: str) -> str:
    p = Path(dotenv)
    if p.is_absolute():
        return str(p)
    candidate = (repo_root / p).resolve()
    if candidate.exists():
        return str(candidate)
    return dotenv


def resolve_code_runner(name: str | None) -> str:
    key = (name or "mini").strip().lower()
    if key in {"mini", "mini-js", "minicode"}:
        return "mini"
    if key in {"python", "python-subprocess", "subprocess-python"}:
        return "python-subprocess"
    raise ValueError(f"unknown code runner: {name}")


def resolve_browser_driver(name: str | None) -> str:
    key = (name or "memory").strip().lower()
    if key in {"memory", "in-memory", "fake"}:
        return "memory"
    if key in {"playwright", "pw"}:
        return "playwright"
    raise ValueError(f"unknown browser driver: {name}")


def _build_real_cantrip(
    repo_root: Path,
    *,
    code_runner: str | None = None,
    browser_driver: str | None = None,
) -> Cantrip:
    model = os.getenv("CANTRIP_OPENAI_MODEL")
    base_url = os.getenv("CANTRIP_OPENAI_BASE_URL")
    if not model or not base_url:
        raise RuntimeError(
            "missing env: CANTRIP_OPENAI_MODEL and CANTRIP_OPENAI_BASE_URL are required"
        )

    crystal = OpenAICompatCrystal(
        model=model,
        base_url=base_url,
        api_key=os.getenv("CANTRIP_OPENAI_API_KEY", ""),
        timeout_s=float(os.getenv("CANTRIP_OPENAI_TIMEOUT_S", "30")),
    )
    max_turns = int(os.getenv("CANTRIP_CAPSTONE_MAX_TURNS", "6"))
    max_depth = int(os.getenv("CANTRIP_CAPSTONE_MAX_DEPTH", "2"))
    medium = os.getenv("CANTRIP_CAPSTONE_MEDIUM", "text").strip().lower()
    if medium not in {"text", "code", "browser"}:
        medium = "text"

    resolved_runner = resolve_code_runner(
        code_runner or os.getenv("CANTRIP_CAPSTONE_CODE_RUNNER", "mini")
    )
    resolved_driver = resolve_browser_driver(
        browser_driver or os.getenv("CANTRIP_CAPSTONE_BROWSER_DRIVER", "memory")
    )

    circle = Circle(
        medium=("tool" if medium == "text" else medium),
        depends={
            "code": {
                "runner": resolved_runner,
                "timeout_s": float(os.getenv("CANTRIP_CAPSTONE_CODE_TIMEOUT_S", "5")),
            },
            "browser": {"driver": resolved_driver},
        },
        gates=[
            {
                "name": "done",
                "parameters": {
                    "type": "object",
                    "properties": {"answer": {"type": "string"}},
                    "required": ["answer"],
                },
            },
            "call_entity",
            "call_entity_batch",
            {"name": "repo_files", "depends": {"root": str(repo_root)}},
            {"name": "repo_read", "depends": {"root": str(repo_root)}},
        ],
        wards=[{"max_turns": max_turns}, {"max_depth": max_depth}],
    )
    call = Call(
        system_prompt=(
            "You are a coding agent working inside this repository. "
            "Use repo_files and repo_read to inspect code, and call_entity/call_entity_batch "
            "for delegation. Prefer a single concise answer. "
            "In code medium, finish by calling done(answer)."
        ),
        tool_choice="required" if medium == "code" else None,
        require_done_tool=(medium == "code"),
    )
    return Cantrip(crystal=crystal, circle=circle, call=call)


def _build_fake_cantrip(
    repo_root: Path,
    *,
    code_runner: str | None = None,
    browser_driver: str | None = None,
) -> Cantrip:
    medium = os.getenv("CANTRIP_CAPSTONE_MEDIUM", "text").strip().lower()
    if medium not in {"text", "code", "browser"}:
        medium = "text"

    crystal = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {
                            "gate": "repo_files",
                            "args": {"glob": "cantrip/*.py", "limit": 3},
                        },
                        {"gate": "done", "args": {"answer": "fake-ok"}},
                    ]
                }
            ]
        }
    )
    resolved_runner = resolve_code_runner(
        code_runner or os.getenv("CANTRIP_CAPSTONE_CODE_RUNNER", "mini")
    )
    resolved_driver = resolve_browser_driver(
        browser_driver or os.getenv("CANTRIP_CAPSTONE_BROWSER_DRIVER", "memory")
    )
    circle = Circle(
        medium=("tool" if medium == "text" else medium),
        depends={
            "code": {"runner": resolved_runner},
            "browser": {"driver": resolved_driver},
        },
        gates=[
            {
                "name": "done",
                "parameters": {
                    "type": "object",
                    "properties": {"answer": {"type": "string"}},
                    "required": ["answer"],
                },
            },
            {"name": "repo_files", "depends": {"root": str(repo_root)}},
            {"name": "repo_read", "depends": {"root": str(repo_root)}},
        ],
        wards=[{"max_turns": 8}],
    )
    return Cantrip(crystal=crystal, circle=circle)


def build_cantrip_from_env(
    *,
    repo_root: Path,
    dotenv: str = ".env",
    fake: bool = False,
    code_runner: str | None = None,
    browser_driver: str | None = None,
) -> Cantrip:
    """Build the default capstone cantrip from environment configuration."""
    load_dotenv_if_present(_resolve_dotenv_path(repo_root, dotenv))
    if fake:
        return _build_fake_cantrip(
            repo_root,
            code_runner=code_runner,
            browser_driver=browser_driver,
        )
    return _build_real_cantrip(
        repo_root,
        code_runner=code_runner,
        browser_driver=browser_driver,
    )
