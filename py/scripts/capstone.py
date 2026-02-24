#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from cantrip import (
    Call,
    Cantrip,
    Circle,
    FakeCrystal,
    OpenAICompatCrystal,
    serve_stdio,
)
from cantrip.acp_server import CantripACPServer
from cantrip.env import load_dotenv_if_present


def _resolve_code_runner(name: str) -> str:
    key = (name or "mini").strip().lower()
    if key in {"mini", "mini-js", "minicode"}:
        return "mini"
    if key in {"python", "python-subprocess", "subprocess-python"}:
        return "python-subprocess"
    raise SystemExit(f"Unknown code runner: {name}")


def _resolve_browser_driver(name: str) -> str:
    key = (name or "memory").strip().lower()
    if key in {"memory", "in-memory", "fake"}:
        return "memory"
    if key in {"playwright", "pw"}:
        return "playwright"
    raise SystemExit(f"Unknown browser driver: {name}")


def build_real_cantrip(
    repo_root: Path,
    *,
    code_runner: str | None = None,
    browser_driver: str | None = None,
) -> Cantrip:
    model = os.getenv("CANTRIP_OPENAI_MODEL")
    base_url = os.getenv("CANTRIP_OPENAI_BASE_URL")
    if not model or not base_url:
        raise SystemExit(
            "Missing env: CANTRIP_OPENAI_MODEL and CANTRIP_OPENAI_BASE_URL are required."
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
    runner_name = code_runner or os.getenv("CANTRIP_CAPSTONE_CODE_RUNNER", "mini")
    driver_name = browser_driver or os.getenv(
        "CANTRIP_CAPSTONE_BROWSER_DRIVER", "memory"
    )
    if medium not in {"text", "code", "browser"}:
        medium = "text"
    resolved_runner = _resolve_code_runner(runner_name)
    resolved_driver = _resolve_browser_driver(driver_name)
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
    return Cantrip(
        crystal=crystal,
        circle=circle,
        call=call,
    )


def build_fake_cantrip(
    repo_root: Path,
    *,
    code_runner: str | None = None,
    browser_driver: str | None = None,
) -> Cantrip:
    medium = os.getenv("CANTRIP_CAPSTONE_MEDIUM", "text").strip().lower()
    if medium not in {"text", "code", "browser"}:
        medium = "text"
    circle_medium = "tool" if medium == "text" else medium
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
    runner_name = code_runner or os.getenv("CANTRIP_CAPSTONE_CODE_RUNNER", "mini")
    driver_name = browser_driver or os.getenv(
        "CANTRIP_CAPSTONE_BROWSER_DRIVER", "memory"
    )
    resolved_runner = _resolve_code_runner(runner_name)
    resolved_driver = _resolve_browser_driver(driver_name)
    circle = Circle(
        medium=circle_medium,
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
    return Cantrip(
        crystal=crystal,
        circle=circle,
    )


def build_cantrip(
    *,
    repo_root: Path,
    dotenv: str,
    fake: bool,
    code_runner: str | None = None,
    browser_driver: str | None = None,
) -> Cantrip:
    load_dotenv_if_present(dotenv)
    return (
        build_fake_cantrip(
            repo_root,
            code_runner=code_runner,
            browser_driver=browser_driver,
        )
        if fake
        else build_real_cantrip(
            repo_root,
            code_runner=code_runner,
            browser_driver=browser_driver,
        )
    )


def cmd_repl(args: argparse.Namespace) -> int:
    cantrip = build_cantrip(
        repo_root=Path(args.repo_root).resolve(),
        dotenv=args.dotenv,
        fake=args.fake,
        code_runner=args.code_runner,
        browser_driver=args.browser_driver,
    )
    server = CantripACPServer(cantrip)
    session_id = server.create_session()

    print(f"session: {session_id}")
    print("enter an intent (`:q` to quit)")
    while True:
        try:
            intent = input("> ").strip()
        except EOFError:
            break
        if not intent:
            continue
        if intent in {":q", ":quit", ":exit"}:
            break
        payload = server.cast(session_id=session_id, intent=intent)
        print(f"\nresult:\n{payload['result']}\n")
        for ev in payload["events"]:
            if ev["type"] == "tool_result":
                status = "error" if ev["is_error"] else "ok"
                print(f"[tool:{ev['gate']}] {status}")
        print()

    server.close_session(session_id)
    return 0


def cmd_pipe(args: argparse.Namespace) -> int:
    cantrip = build_cantrip(
        repo_root=Path(args.repo_root).resolve(),
        dotenv=args.dotenv,
        fake=args.fake,
        code_runner=args.code_runner,
        browser_driver=args.browser_driver,
    )
    server = CantripACPServer(cantrip)
    session_id = server.create_session()
    for raw in sys.stdin:
        intent = raw.strip()
        if not intent or intent.startswith("#"):
            continue
        if intent in {":q", ":quit", ":exit"}:
            break
        payload = server.cast(session_id=session_id, intent=intent)
        out = {
            "intent": intent,
            "session_id": session_id,
            "thread_id": payload["thread_id"],
            "result": payload["result"],
        }
        if args.with_events:
            out["events"] = payload["events"]
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()
    server.close_session(session_id)
    return 0


def cmd_acp_stdio(args: argparse.Namespace) -> int:
    cantrip = build_cantrip(
        repo_root=Path(args.repo_root).resolve(),
        dotenv=args.dotenv,
        fake=args.fake,
        code_runner=args.code_runner,
        browser_driver=args.browser_driver,
    )
    serve_stdio(cantrip, sys.stdin, sys.stdout)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Capstone entity CLI. Default mode is pipe "
            "(stdin intents -> JSONL output)."
        )
    )
    parser.add_argument("--repo-root", default=".", help="Repo root for repo_* gates.")
    parser.add_argument("--dotenv", default=".env", help="Dotenv file to load.")
    parser.add_argument(
        "--fake", action="store_true", help="Use FakeCrystal (offline)."
    )
    parser.add_argument(
        "--with-events",
        action="store_true",
        help="Include ACP events in output (pipe mode only).",
    )
    parser.add_argument(
        "--code-runner",
        default=None,
        help="Code runner: mini|python-subprocess (or set CANTRIP_CAPSTONE_CODE_RUNNER).",
    )
    parser.add_argument(
        "--browser-driver",
        default=None,
        help="Browser driver: memory|playwright (or set CANTRIP_CAPSTONE_BROWSER_DRIVER).",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--repl", action="store_true", help="Run interactive REPL mode.")
    mode.add_argument(
        "--acp-stdio",
        action="store_true",
        help="Run ACP stdio service mode.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.repl:
        return int(cmd_repl(args))
    if args.acp_stdio:
        return int(cmd_acp_stdio(args))
    return int(cmd_pipe(args))


if __name__ == "__main__":
    raise SystemExit(main())
