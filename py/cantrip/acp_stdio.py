from __future__ import annotations

import json
import os
import sys
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, TextIO

from acp import (
    SessionNotification,
    start_tool_call,
    update_agent_message_text,
    update_agent_thought_text,
    update_tool_call,
)

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

    def _streaming_progress(
        self,
        progress: dict[str, Any],
        event: dict[str, Any],
    ) -> dict[str, Any]:
        updated = dict(progress)
        kind = event.get("type")
        if kind == "step_start":
            updated["steps"] = int(updated.get("steps", 0)) + 1
        elif kind == "tool_result":
            updated["tool_calls"] = int(updated.get("tool_calls", 0)) + 1
            gates = list(updated.get("gates") or [])
            gate = event.get("gate")
            if gate:
                gates.append(str(gate))
                updated["last_gate"] = str(gate)
            updated["gates"] = gates
            if event.get("is_error") is True:
                updated["tool_errors"] = int(updated.get("tool_errors", 0)) + 1
                content = event.get("content")
                if content:
                    updated["last_error"] = str(content)
        return updated

    def _progress_text(self, progress: dict[str, Any]) -> str:
        parts = [
            f"progress: steps={int(progress.get('steps', 0))}",
            f"tools={int(progress.get('tool_calls', 0))}",
            f"errors={int(progress.get('tool_errors', 0))}",
        ]
        last_gate = progress.get("last_gate")
        if last_gate:
            parts.append(f"last_gate={last_gate}")
        last_error = progress.get("last_error")
        if last_error:
            parts.append(f"last_error={last_error}")
        return " | ".join(parts) + "\n"

    def _tool_kind(self, gate: str) -> str:
        key = (gate or "").strip().lower()
        if key == "repo_read":
            return "read"
        if key == "repo_files":
            return "search"
        if key in {"code", "call_entity", "call_entity_batch"}:
            return "execute"
        return "other"

    def _emit_session_update(
        self,
        *,
        emit_notification: Callable[[dict[str, Any]], None] | None,
        session_id: str,
        update: Any,
    ) -> None:
        if emit_notification is None:
            return
        note = SessionNotification(sessionId=session_id, update=update)
        emit_notification(
            {
                "method": "session/update",
                "params": note.model_dump(by_alias=True, exclude_none=True),
            }
        )

    def handle(
        self,
        request: dict[str, Any],
        *,
        emit_notification: Callable[[dict[str, Any]], None] | None = None,
    ) -> dict[str, Any]:
        req_id = request.get("id")
        method = request.get("method")
        params = request.get("params") or {}

        try:
            if method in {"initialize", "session/initialize", "session.initialize"}:
                requested_proto = (params or {}).get("protocolVersion", 1)
                return {
                    "id": req_id,
                    "result": {
                        "protocolVersion": requested_proto,
                        "agentInfo": {"name": "cantrip-py", "version": "0.2.0"},
                        "capabilities": {
                            "session/new": True,
                            "session.new": True,
                            "session/prompt": True,
                            "session.prompt": True,
                            "session/cancel": True,
                            "session.cancel": True,
                            "session/update": True,
                            "session.update": True,
                        },
                        "agentCapabilities": {
                            "loadSession": False,
                            "promptCapabilities": {"image": False},
                            "modes": [
                                {
                                    "id": "default",
                                    "name": "Default",
                                    "description": "Standard assistant behavior.",
                                }
                            ],
                            "defaultModeId": "default",
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
            if method in {"session.create", "session/new", "session.new"}:
                session_id = self.server.create_session()
                return {
                    "id": req_id,
                    "result": {"session_id": session_id, "sessionId": session_id},
                }
            if method in {
                "session/set_mode",
                "session/setMode",
                "session.setMode",
                "session/set-mode",
            }:
                sid = self._extract_session_id(params)
                if not sid:
                    raise KeyError("session_id")
                mode_id = (
                    params.get("modeId")
                    or params.get("mode_id")
                    or params.get("mode")
                    or "default"
                )
                return {
                    "id": req_id,
                    "result": {"sessionId": sid, "session_id": sid, "modeId": mode_id},
                }
            if method in {"session.exists", "session/exists"}:
                sid = self._extract_session_id(params)
                if not sid:
                    raise KeyError("session_id")
                exists = self.server.session_exists(sid)
                return {"id": req_id, "result": {"exists": exists}}
            if method in {
                "session.close",
                "session/close",
            }:
                sid = self._extract_session_id(params)
                if not sid:
                    raise KeyError("session_id")
                closed = self.server.close_session(sid)
                return {"id": req_id, "result": {"closed": closed}}
            if method in {"session/cancel", "session.cancel"}:
                sid = self._extract_session_id(params)
                if not sid:
                    raise KeyError("session_id")
                cancelled = self.server.request_cancel(sid)
                return {
                    "id": req_id,
                    "result": {
                        "cancelled": cancelled,
                        "sessionId": sid,
                        "session_id": sid,
                    },
                }
            if method == "cast":
                sid = self._extract_session_id(params)
                if not sid:
                    raise KeyError("session_id")
                payload = self.server.cast(
                    session_id=sid,
                    intent=str(params["intent"]),
                )
                return {"id": req_id, "result": payload}
            if method in {"session/prompt", "session.prompt"}:
                sid = self._extract_session_id(params)
                if not sid:
                    sid = self.server.create_session()
                intent = self._extract_intent(params)
                if not intent:
                    raise KeyError("prompt")
                try:
                    stream_events: list[dict[str, Any]] = []
                    stream_progress = {
                        "steps": 0,
                        "tool_calls": 0,
                        "tool_errors": 0,
                        "gates": [],
                    }
                    last_thought_step = 0
                    last_thought_errors = 0

                    def _on_event(event: dict[str, Any]) -> None:
                        nonlocal stream_progress, last_thought_step, last_thought_errors
                        if not isinstance(event, dict):
                            return
                        stream_events.append(event)
                        stream_progress = self._streaming_progress(
                            stream_progress, event
                        )
                        if emit_notification is None:
                            return
                        if event.get("type") == "step_complete":
                            step_now = int(stream_progress.get("steps", 0))
                            errors_now = int(stream_progress.get("tool_errors", 0))
                            should_emit = (
                                step_now == 1
                                or errors_now > last_thought_errors
                                or (step_now - last_thought_step) >= 2
                            )
                            if not should_emit:
                                return
                            last_thought_step = step_now
                            last_thought_errors = errors_now
                            self._emit_session_update(
                                emit_notification=emit_notification,
                                session_id=sid,
                                update=update_agent_thought_text(
                                    self._progress_text(stream_progress)
                                ),
                            )
                            return
                        if event.get("type") == "tool_result":
                            gate = str(event.get("gate") or "tool")
                            turn_id = str(event.get("turn_id") or "turn")
                            idx = int(stream_progress.get("tool_calls", 0))
                            tool_call_id = f"{turn_id}:{idx}"
                            status = "failed" if event.get("is_error") else "completed"
                            title = gate
                            raw_input = event.get("arguments")
                            raw_output = (
                                event.get("content")
                                if event.get("is_error")
                                else event.get("result")
                            )
                            self._emit_session_update(
                                emit_notification=emit_notification,
                                session_id=sid,
                                update=start_tool_call(
                                    tool_call_id,
                                    title,
                                    kind=self._tool_kind(gate),
                                    status="in_progress",
                                    raw_input=raw_input,
                                ),
                            )
                            self._emit_session_update(
                                emit_notification=emit_notification,
                                session_id=sid,
                                update=update_tool_call(
                                    tool_call_id,
                                    title=title,
                                    kind=self._tool_kind(gate),
                                    status=status,
                                    raw_input=raw_input,
                                    raw_output=raw_output,
                                ),
                            )

                    payload = self.server.cast(
                        session_id=sid,
                        intent=intent,
                        event_sink=_on_event,
                    )
                    text = str(payload.get("assistant_text", ""))
                    stop_reason = str(payload.get("stop_reason") or "end_turn")
                    progress = self._progress_summary(
                        payload.get("events") or stream_events or []
                    )
                    timing = payload.get("timing") or {}
                    thread_id = payload.get("thread_id")
                    result_value = payload.get("result")
                    events = payload.get("events") or stream_events or []
                    error_obj = None
                    if (
                        result_value is None
                        and stop_reason
                        in {"max_turn_requests", "cancelled", "end_turn"}
                        and text.startswith("No final answer produced")
                    ):
                        error_obj = {
                            "type": "non_terminal_outcome",
                            "reason": stop_reason,
                            "message": text,
                        }
                except Exception as e:  # noqa: BLE001
                    text = f"Error: {e}"
                    progress = {
                        "steps": 0,
                        "tool_calls": 0,
                        "tool_errors": 1,
                        "gates": [],
                    }
                    stop_reason = "end_turn"
                    timing = {}
                    thread_id = None
                    result_value = None
                    events = []
                    error_obj = {"type": "internal_error", "message": str(e)}
                return {
                    "id": req_id,
                    "result": {
                        "stopReason": stop_reason,
                        "output": [{"type": "text", "text": text}],
                        "sessionId": sid,
                        "session_id": sid,
                        "threadId": thread_id,
                        "thread_id": thread_id,
                        "_meta": {
                            "sessionId": sid,
                            "threadId": thread_id,
                            "result": result_value,
                            "assistantText": text,
                            "events": events,
                            "progress": progress,
                            "timing": timing,
                            "error": error_obj,
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
        if method not in {"session/prompt", "session.prompt"}:
            return []
        result = response.get("result") or {}
        meta = result.get("_meta") or {}
        session_id = meta.get("sessionId")
        if not session_id:
            return []
        text = str(meta.get("assistantText", ""))
        chunk_obj = update_agent_message_text(text).model_dump(
            by_alias=True, exclude_none=True
        )
        content_obj = update_agent_message_text(text).model_dump(
            by_alias=True, exclude_none=True
        )
        return [
            {
                "method": "session/update",
                "params": {
                    "sessionId": session_id,
                    "update": {
                        "sessionUpdate": "agent_message_chunk",
                        "content": chunk_obj["content"],
                    },
                },
            },
            {
                "method": "session/update",
                "params": {
                    "sessionId": session_id,
                    "update": {
                        "sessionUpdate": "agent_message",
                        "content": content_obj["content"],
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

        def _emit_notification(payload: dict[str, Any]) -> None:
            payload["jsonrpc"] = "2.0"
            _debug_log(f"[acp notify] {json.dumps(payload)}")
            out.write(json.dumps(payload) + "\n")
            out.flush()

        response = router.handle(request, emit_notification=_emit_notification)
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

            def _emit_notification(payload: dict[str, Any]) -> None:
                payload["jsonrpc"] = "2.0"
                _debug_log(f"[acp notify] {json.dumps(payload)}")
                out.write(json.dumps(payload) + "\n")
                out.flush()

            response = router.handle(request, emit_notification=_emit_notification)
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
