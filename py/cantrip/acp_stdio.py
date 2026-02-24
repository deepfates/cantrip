from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from typing import Any, TextIO

from cantrip.acp_server import CantripACPServer
from cantrip.runtime import Cantrip


def _debug_enabled() -> bool:
    return bool(os.getenv("CANTRIP_ACP_DEBUG") or os.getenv("CANTRIP_ACP_DEBUG_FILE"))


def _debug_log(line: str) -> None:
    if not _debug_enabled():
        return
    path = os.getenv("CANTRIP_ACP_DEBUG_FILE", ".cantrip_acp_debug.log")
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(line.rstrip("\n") + "\n")
    except Exception:  # noqa: BLE001
        pass


@dataclass
class ACPStdioRouter:
    """Line-oriented JSON router for a thin ACP-like stdio transport."""

    cantrip: Cantrip

    def __post_init__(self) -> None:
        self.server = CantripACPServer(self.cantrip)

    def _extract_session_id(self, params: dict[str, Any]) -> str | None:
        sid = params.get("session_id")
        if sid is None:
            sid = params.get("sessionId")
        return str(sid) if sid else None

    def _extract_intent(self, params: dict[str, Any]) -> str:
        if params.get("intent"):
            return str(params["intent"])
        if params.get("message"):
            return str(params["message"])
        prompt = params.get("prompt")
        if isinstance(prompt, str):
            return prompt
        if isinstance(prompt, list):
            parts: list[str] = []
            for block in prompt:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text":
                    txt = block.get("text")
                    if txt:
                        parts.append(str(txt))
            if parts:
                return "\n".join(parts)
        content = params.get("content")
        if isinstance(content, list):
            parts = []
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text":
                    txt = block.get("text")
                    if txt:
                        parts.append(str(txt))
            if parts:
                return "\n".join(parts)
        return ""

    def _progress_summary(self, events: list[dict[str, Any]]) -> dict[str, Any]:
        steps = 0
        tools = 0
        errors = 0
        gates: list[str] = []
        for ev in events:
            if not isinstance(ev, dict):
                continue
            if ev.get("type") == "step_start":
                steps += 1
            if ev.get("type") == "tool_result":
                tools += 1
                gate = ev.get("gate")
                if gate:
                    gates.append(str(gate))
                if ev.get("is_error") is True:
                    errors += 1
        return {
            "steps": steps,
            "tool_calls": tools,
            "tool_errors": errors,
            "gates": gates,
        }

    def _progress_text(self, progress: dict[str, Any]) -> str:
        return (
            "progress:"
            f" steps={progress['steps']}"
            f" tools={progress['tool_calls']}"
            f" errors={progress['tool_errors']}"
        )

    def handle(self, request: dict[str, Any]) -> dict[str, Any]:
        req_id = request.get("id")
        method = request.get("method")
        params = request.get("params") or {}

        try:
            if method in {"initialize", "session/initialize"}:
                requested_proto = (params or {}).get("protocolVersion", 1)
                return {
                    "id": req_id,
                    "result": {
                        "protocolVersion": requested_proto,
                        "agentInfo": {"name": "cantrip-py", "version": "0.2.0"},
                        "capabilities": {
                            "session/new": True,
                            "session/prompt": True,
                            "session/cancel": True,
                        },
                        "agentCapabilities": {
                            "sessionCapabilities": {
                                "new": True,
                                "prompt": True,
                                "cancel": True,
                                "update": True,
                            },
                        },
                    },
                }
            if method == "authenticate":
                return {"id": req_id, "result": {"authenticated": True}}
            if method in {"session.create", "session/new"}:
                session_id = self.server.create_session()
                return {
                    "id": req_id,
                    "result": {"session_id": session_id, "sessionId": session_id},
                }
            if method in {"session.exists", "session/exists"}:
                sid = self._extract_session_id(params)
                if not sid:
                    raise KeyError("session_id")
                exists = self.server.session_exists(sid)
                return {"id": req_id, "result": {"exists": exists}}
            if method in {"session.close", "session/close", "session/cancel"}:
                sid = self._extract_session_id(params)
                if not sid:
                    raise KeyError("session_id")
                closed = self.server.close_session(sid)
                return {"id": req_id, "result": {"closed": closed}}
            if method == "cast":
                sid = self._extract_session_id(params)
                if not sid:
                    raise KeyError("session_id")
                payload = self.server.cast(
                    session_id=sid,
                    intent=str(params["intent"]),
                )
                return {"id": req_id, "result": payload}
            if method == "session/prompt":
                sid = self._extract_session_id(params)
                if not sid:
                    sid = self.server.create_session()
                intent = self._extract_intent(params)
                if not intent:
                    raise KeyError("prompt")
                payload = self.server.cast(session_id=sid, intent=intent)
                text = str(payload.get("assistant_text", ""))
                progress = self._progress_summary(payload.get("events") or [])
                return {
                    "id": req_id,
                    "result": {
                        "stopReason": "end_turn",
                        "output": [{"type": "text", "text": text}],
                        "sessionId": sid,
                        "session_id": sid,
                        "threadId": payload["thread_id"],
                        "thread_id": payload["thread_id"],
                        "_meta": {
                            "sessionId": sid,
                            "threadId": payload["thread_id"],
                            "result": payload["result"],
                            "assistantText": text,
                            "events": payload["events"],
                            "progress": progress,
                        },
                    },
                }
            return {
                "id": req_id,
                "error": {
                    "code": "method_not_found",
                    "message": f"unknown method: {method}",
                },
            }
        except KeyError as e:
            return {
                "id": req_id,
                "error": {"code": "invalid_request", "message": str(e)},
            }
        except Exception as e:  # noqa: BLE001
            return {
                "id": req_id,
                "error": {"code": "internal_error", "message": str(e)},
            }

    def is_request(self, payload: Any) -> bool:
        return isinstance(payload, dict) and isinstance(payload.get("method"), str)

    def notifications_for(
        self, request: dict[str, Any], response: dict[str, Any]
    ) -> list[dict[str, Any]]:
        method = request.get("method")
        if method != "session/prompt":
            return []
        result = response.get("result") or {}
        meta = result.get("_meta") or {}
        session_id = meta.get("sessionId")
        if not session_id:
            return []
        text = str(meta.get("assistantText", ""))
        progress = meta.get("progress") or {
            "steps": 0,
            "tool_calls": 0,
            "tool_errors": 0,
            "gates": [],
        }
        chunk_obj = {"type": "text", "text": self._progress_text(progress)}
        content_obj = {"type": "text", "text": text}
        return [
            {
                "method": "session/update",
                "params": {
                    "sessionId": session_id,
                    "update": {
                        "sessionUpdate": "agent_message_chunk",
                        "content": chunk_obj,
                    },
                },
            },
            {
                "method": "session/update",
                "params": {
                    "sessionId": session_id,
                    "update": {
                        "sessionUpdate": "agent_message",
                        "content": content_obj,
                    },
                },
            },
        ]


def serve_stdio_once(cantrip: Cantrip, inp: TextIO, out: TextIO) -> None:
    """Read one JSON line request and write one JSON line response."""
    router = ACPStdioRouter(cantrip)
    raw = inp.readline()
    if not raw:
        return
    try:
        request = json.loads(raw)
        _debug_log(f"[acp req] {json.dumps(request)}")
        if not router.is_request(request):
            return
        response = router.handle(request)
        notifications = router.notifications_for(request, response)
    except Exception as e:  # noqa: BLE001
        response = {"id": None, "error": {"code": "parse_error", "message": str(e)}}
        notifications = []
    response["jsonrpc"] = "2.0"
    for n in notifications:
        n["jsonrpc"] = "2.0"
        _debug_log(f"[acp notify] {json.dumps(n)}")
        out.write(json.dumps(n) + "\n")
    _debug_log(f"[acp resp] {json.dumps(response)}")
    out.write(json.dumps(response) + "\n")
    out.flush()


def serve_stdio(cantrip: Cantrip, inp: TextIO, out: TextIO) -> None:
    """Process newline-delimited JSON requests until EOF."""
    router = ACPStdioRouter(cantrip)
    while True:
        raw = inp.readline()
        if not raw:
            break
        try:
            request = json.loads(raw)
            _debug_log(f"[acp req] {json.dumps(request)}")
            if not router.is_request(request):
                continue
            response = router.handle(request)
            notifications = router.notifications_for(request, response)
        except Exception as e:  # noqa: BLE001
            response = {"id": None, "error": {"code": "parse_error", "message": str(e)}}
            notifications = []
        response["jsonrpc"] = "2.0"
        for n in notifications:
            n["jsonrpc"] = "2.0"
            _debug_log(f"[acp notify] {json.dumps(n)}")
            out.write(json.dumps(n) + "\n")
        _debug_log(f"[acp resp] {json.dumps(response)}")
        out.write(json.dumps(response) + "\n")
        out.flush()


def main() -> int:
    """Minimal interactive stdio loop for local ACP protocol experiments."""
    sys.stderr.write(
        "acp stdio entrypoint requires explicit cantrip wiring by host application\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
