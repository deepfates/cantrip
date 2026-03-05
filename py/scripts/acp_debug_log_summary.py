#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any


def _parse_line(line: str) -> tuple[str, dict[str, Any]] | None:
    line = line.strip()
    if not line:
        return None
    for prefix in ("[acp req] ", "[acp resp] ", "[acp notify] "):
        if line.startswith(prefix):
            payload = json.loads(line[len(prefix) :])
            return prefix.strip(), payload
    return None


def summarize(path: Path) -> dict[str, Any]:
    req_methods: Counter[str] = Counter()
    resp_errors: list[dict[str, Any]] = []
    notify_types: Counter[str] = Counter()
    total = 0

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        parsed = _parse_line(raw)
        if not parsed:
            continue
        kind, payload = parsed
        total += 1

        if kind == "[acp req]":
            method = payload.get("method")
            if isinstance(method, str):
                req_methods[method] += 1
        elif kind == "[acp resp]":
            if isinstance(payload.get("error"), dict):
                resp_errors.append(payload["error"])
        elif kind == "[acp notify]":
            update = ((payload.get("params") or {}).get("update") or {}).get(
                "sessionUpdate"
            )
            if isinstance(update, str):
                notify_types[update] += 1

    return {
        "path": str(path),
        "events": total,
        "request_methods": dict(req_methods),
        "notifications": dict(notify_types),
        "response_errors": resp_errors,
        "ok": "initialize" in req_methods and (
            "session/prompt" in req_methods or "session.prompt" in req_methods
        ),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Summarize cantrip ACP debug log")
    parser.add_argument("--log", default=".cantrip_acp_debug.log", help="ACP debug log file")
    args = parser.parse_args(argv)

    path = Path(args.log)
    if not path.exists():
        print(json.dumps({"ok": False, "error": f"log not found: {path}"}, indent=2))
        return 1

    summary = summarize(path)
    print(json.dumps(summary, indent=2))
    return 0 if summary.get("ok") else 2


if __name__ == "__main__":
    raise SystemExit(main())
