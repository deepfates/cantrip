from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from cantrip.acp_server import CantripACPServer
from cantrip.acp_stdio import serve_stdio
from cantrip.builders import build_cantrip_from_env


def cmd_repl(args: argparse.Namespace) -> int:
    cantrip = build_cantrip_from_env(
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
    cantrip = build_cantrip_from_env(
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
    cantrip = build_cantrip_from_env(
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
        prog="cantrip",
        description=(
            "Cantrip runtime CLI. Defaults to pipe mode when no subcommand is provided "
            "(stdin intents -> JSONL output)."
        ),
        epilog=(
            "Examples:\n"
            "  cantrip --fake pipe\n"
            "  cantrip --fake repl\n"
            "  cantrip --fake acp-stdio\n\n"
            "Config precedence:\n"
            "  CLI flags override environment variables (CANTRIP_CAPSTONE_*) "
            "which override built-in defaults."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("--repo-root", default=".", help="Repo root for repo_* gates.")
    parser.add_argument("--dotenv", default=".env", help="Dotenv file to load.")
    parser.add_argument(
        "--fake", action="store_true", help="Use FakeCrystal (offline mode)."
    )
    parser.add_argument(
        "--with-events",
        action="store_true",
        help="Include ACP events in output (pipe mode only).",
    )
    parser.add_argument(
        "--code-runner",
        default=None,
        choices=["mini", "python-subprocess"],
        help="Code runner override (or set CANTRIP_CAPSTONE_CODE_RUNNER).",
    )
    parser.add_argument(
        "--browser-driver",
        default=None,
        choices=["memory", "playwright"],
        help="Browser driver override (or set CANTRIP_CAPSTONE_BROWSER_DRIVER).",
    )

    # Legacy mode flags retained for compatibility with existing scripts/tests.
    legacy_mode = parser.add_mutually_exclusive_group()
    legacy_mode.add_argument("--repl", action="store_true", help=argparse.SUPPRESS)
    legacy_mode.add_argument("--acp-stdio", action="store_true", help=argparse.SUPPRESS)

    sub = parser.add_subparsers(dest="command")
    sub.add_parser("pipe", help="Run pipe mode (default).")
    sub.add_parser("repl", help="Run interactive REPL mode.")
    sub.add_parser("acp-stdio", help="Run ACP stdio service mode.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command:
        mode = args.command
    elif args.repl:
        mode = "repl"
    elif args.acp_stdio:
        mode = "acp-stdio"
    else:
        mode = "pipe"

    if mode == "repl":
        return int(cmd_repl(args))
    if mode == "acp-stdio":
        return int(cmd_acp_stdio(args))
    return int(cmd_pipe(args))


if __name__ == "__main__":
    raise SystemExit(main())
