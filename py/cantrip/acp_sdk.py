from __future__ import annotations

import asyncio
import json
import os
from concurrent.futures import Future
from typing import Any

from acp import (
    run_agent,
    start_tool_call,
    update_agent_message_text,
    update_agent_thought_text,
    update_tool_call,
)
from acp.connection import StreamDirection, StreamEvent

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


class CantripACPAgent:
    def __init__(self, cantrip: Cantrip) -> None:
        self.server = CantripACPServer(cantrip)
        self._client = None

    def on_connect(self, conn) -> None:
        self._client = conn

    async def initialize(
        self,
        protocol_version: int,
        client_capabilities=None,  # noqa: ARG002
        client_info=None,  # noqa: ARG002
        **kwargs: Any,  # noqa: ARG002
    ) -> dict[str, Any]:
        return {
            "protocolVersion": protocol_version,
            "agentInfo": {"name": "cantrip-py", "version": "0.2.0"},
            "capabilities": {
                "session/new": True,
                "session/prompt": True,
                "session/cancel": True,
                "session/update": True,
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
        }

    async def authenticate(self, method_id: str, **kwargs: Any) -> dict[str, Any]:  # noqa: ARG002
        return {"authenticated": True}

    async def new_session(
        self,
        cwd: str,
        mcp_servers=None,
        **kwargs: Any,  # noqa: ARG002
    ) -> dict[str, Any]:
        sid = self.server.create_session()
        return {"sessionId": sid, "session_id": sid}

    async def set_session_mode(
        self,
        mode_id: str,
        session_id: str,
        **kwargs: Any,  # noqa: ARG002
    ) -> dict[str, Any]:
        if not self.server.session_exists(session_id):
            raise KeyError("session_id")
        return {"sessionId": session_id, "session_id": session_id, "modeId": mode_id}

    async def cancel(self, session_id: str, **kwargs: Any) -> None:  # noqa: ARG002
        self.server.request_cancel(session_id)

    def _tool_kind(self, gate: str) -> str:
        key = (gate or "").strip().lower()
        if key == "repo_read":
            return "read"
        if key == "repo_files":
            return "search"
        if key in {"code", "call_entity", "call_entity_batch"}:
            return "execute"
        return "other"

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

    def _streaming_progress(
        self, progress: dict[str, Any], event: dict[str, Any]
    ) -> dict[str, Any]:
        updated = dict(progress)
        kind = event.get("type")
        if kind == "step_start":
            updated["steps"] = int(updated.get("steps", 0)) + 1
        elif kind == "tool_result":
            updated["tool_calls"] = int(updated.get("tool_calls", 0)) + 1
            gate = event.get("gate")
            if gate:
                updated["last_gate"] = str(gate)
            if event.get("is_error") is True:
                updated["tool_errors"] = int(updated.get("tool_errors", 0)) + 1
                content = event.get("content")
                if content:
                    updated["last_error"] = str(content)
        return updated

    async def _send_update(self, session_id: str, update) -> None:
        if self._client is None:
            return
        await self._client.session_update(session_id=session_id, update=update)

    async def prompt(
        self, prompt: list[Any], session_id: str, **kwargs: Any
    ) -> dict[str, Any]:  # noqa: ARG002
        if not self.server.session_exists(session_id):
            session_id = self.server.create_session()
        intent = "\n".join(
            str(getattr(block, "text", ""))
            for block in prompt
            if getattr(block, "type", None) == "text" and getattr(block, "text", None)
        ).strip()
        if not intent:
            raise KeyError("prompt")

        loop = asyncio.get_running_loop()
        stream_progress = {"steps": 0, "tool_calls": 0, "tool_errors": 0}
        last_thought_step = 0
        last_thought_errors = 0
        inflight: list[Future[Any]] = []

        def _emit(update) -> None:
            fut = asyncio.run_coroutine_threadsafe(
                self._send_update(session_id, update), loop
            )
            inflight.append(fut)

        def _on_event(event: dict[str, Any]) -> None:
            nonlocal stream_progress, last_thought_step, last_thought_errors
            if not isinstance(event, dict):
                return
            stream_progress = self._streaming_progress(stream_progress, event)
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
                _emit(
                    start_tool_call(
                        tool_call_id,
                        title,
                        kind=self._tool_kind(gate),
                        status="in_progress",
                        raw_input=raw_input,
                    )
                )
                _emit(
                    update_tool_call(
                        tool_call_id,
                        title=title,
                        kind=self._tool_kind(gate),
                        status=status,
                        raw_input=raw_input,
                        raw_output=raw_output,
                    )
                )
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
                _emit(update_agent_thought_text(self._progress_text(stream_progress)))

        payload = await asyncio.to_thread(
            self.server.cast, session_id=session_id, intent=intent, event_sink=_on_event
        )
        for fut in inflight:
            await asyncio.wrap_future(fut)

        text = str(payload.get("assistant_text", ""))
        await self._send_update(session_id, update_agent_message_text(text))

        stop_reason = str(payload.get("stop_reason") or "end_turn")
        meta = {
            "sessionId": session_id,
            "threadId": payload.get("thread_id"),
            "assistantText": text,
            "result": payload.get("result"),
            "events": payload.get("events") or [],
            "timing": payload.get("timing") or {},
        }
        if (
            payload.get("result") is None
            and stop_reason in {"max_turn_requests", "cancelled", "end_turn"}
            and text.startswith("No final answer produced")
        ):
            meta["error"] = {
                "type": "non_terminal_outcome",
                "reason": stop_reason,
                "message": text,
            }
        else:
            meta["error"] = None
        return {
            "stopReason": stop_reason,
            "output": [{"type": "text", "text": text}],
            "sessionId": session_id,
            "session_id": session_id,
            "threadId": payload.get("thread_id"),
            "thread_id": payload.get("thread_id"),
            "_meta": meta,
        }


def _stream_observer(event: StreamEvent) -> None:
    tag = "req" if event.direction == StreamDirection.INCOMING else "resp"
    msg = event.message
    if tag == "resp" and "method" in msg and "id" not in msg:
        tag = "notify"
    _debug_log(f"[acp {tag}] {json.dumps(msg)}")


async def serve_stdio_sdk_async(cantrip: Cantrip) -> None:
    observers = [_stream_observer] if _debug_enabled() else None
    await run_agent(CantripACPAgent(cantrip), observers=observers)


def serve_stdio_sdk(cantrip: Cantrip) -> None:
    asyncio.run(serve_stdio_sdk_async(cantrip))
