from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING, Any

from cantrip.errors import CantripError
from cantrip.models import Circle, CrystalResponse, GateCallRecord

if TYPE_CHECKING:
    from cantrip.runtime import Cantrip


class Medium(ABC):
    @abstractmethod
    def make_tools(self, circle: Circle) -> list[dict[str, Any]]:
        raise NotImplementedError

    def tool_choice(self, requested: str | None) -> str | None:
        return requested

    @abstractmethod
    def process_response(
        self,
        *,
        cantrip: Cantrip,
        thread,
        response: CrystalResponse,
        current_turn_id: str,
        circle: Circle,
        depth: int | None,
        runtime,
        require_done_tool: bool,
    ) -> tuple[list[GateCallRecord], bool, Any]:
        raise NotImplementedError


class ToolMedium(Medium):
    def make_tools(self, circle: Circle) -> list[dict[str, Any]]:
        out = []
        for name, gate in circle.available_gates().items():
            out.append(
                {
                    "name": name,
                    "parameters": gate.parameters
                    or {"type": "object", "properties": {}},
                }
            )
        return out

    def process_response(
        self,
        *,
        cantrip: Cantrip,
        thread,
        response: CrystalResponse,
        current_turn_id: str,
        circle: Circle,
        depth: int | None,
        runtime,
        require_done_tool: bool,
    ) -> tuple[list[GateCallRecord], bool, Any]:
        observation: list[GateCallRecord] = []
        terminated = False
        result = None

        if response.tool_calls:
            ids = [c.id for c in response.tool_calls]
            if len(set(ids)) != len(ids):
                raise CantripError("duplicate tool call ID")

            for c in response.tool_calls:
                rec = cantrip._execute_gate(
                    thread,
                    c.gate,
                    c.args,
                    parent_turn_id=current_turn_id,
                    circle=circle,
                    depth=depth,
                )
                observation.append(rec)
                if c.gate == "done" and not rec.is_error:
                    terminated = True
                    result = rec.result
                    break
        else:
            if not require_done_tool:
                terminated = True
                result = response.content

        return observation, terminated, result


class CodeMedium(Medium):
    def make_tools(self, circle: Circle) -> list[dict[str, Any]]:
        return [
            {
                "name": "code",
                "parameters": {
                    "type": "object",
                    "properties": {"code": {"type": "string"}},
                    "required": ["code"],
                },
            }
        ]

    def tool_choice(self, requested: str | None) -> str | None:
        return "required" if requested is None else requested

    def process_response(
        self,
        *,
        cantrip: Cantrip,
        thread,
        response: CrystalResponse,
        current_turn_id: str,
        circle: Circle,
        depth: int | None,
        runtime,
        require_done_tool: bool,
    ) -> tuple[list[GateCallRecord], bool, Any]:
        observation: list[GateCallRecord] = []
        terminated = False
        result = None

        if response.content:
            try:
                exec_result = runtime.execute(
                    response.content,
                    call_gate=lambda n, a: cantrip._execute_gate(
                        thread,
                        n,
                        a,
                        parent_turn_id=current_turn_id,
                        circle=circle,
                        depth=depth,
                    ),
                )
                observation.extend(exec_result.observation)
                if exec_result.done:
                    terminated = True
                    result = exec_result.result
                elif not require_done_tool and exec_result.result is not None:
                    terminated = True
                    result = exec_result.result
            except Exception as e:  # noqa: BLE001
                observation.append(
                    GateCallRecord(
                        gate_name="code",
                        arguments={"source": response.content},
                        is_error=True,
                        content=str(e),
                    )
                )
            return observation, terminated, result

        if response.tool_calls:
            for c in response.tool_calls:
                if c.gate == "code":
                    source = (
                        c.args.get("code")
                        or c.args.get("source")
                        or c.args.get("input")
                        or ""
                    )
                    if not str(source).strip():
                        observation.append(
                            GateCallRecord(
                                gate_name="code",
                                arguments={"source": source},
                                is_error=True,
                                content="missing code/source/input",
                            )
                        )
                        continue
                    obs_start = len(observation)
                    try:
                        exec_result = runtime.execute(
                            str(source),
                            call_gate=lambda n, a: cantrip._execute_gate(
                                thread,
                                n,
                                a,
                                parent_turn_id=current_turn_id,
                                circle=circle,
                                depth=depth,
                            ),
                        )
                        observation.extend(exec_result.observation)
                        if len(observation) == obs_start:
                            observation.append(
                                GateCallRecord(
                                    gate_name="code",
                                    arguments={"source": source},
                                    result=(
                                        exec_result.result
                                        if exec_result.result is not None
                                        else ""
                                    ),
                                )
                            )
                        if exec_result.done:
                            terminated = True
                            result = exec_result.result
                            break
                        if not require_done_tool and exec_result.result is not None:
                            terminated = True
                            result = exec_result.result
                            break
                    except Exception as e:  # noqa: BLE001
                        observation.append(
                            GateCallRecord(
                                gate_name="code",
                                arguments={"source": source},
                                is_error=True,
                                content=str(e),
                            )
                        )
                    continue

                rec = cantrip._execute_gate(
                    thread,
                    c.gate,
                    c.args,
                    parent_turn_id=current_turn_id,
                    circle=circle,
                    depth=depth,
                )
                observation.append(rec)
                if c.gate == "done" and not rec.is_error:
                    terminated = True
                    result = rec.result
                    break
            return observation, terminated, result

        return observation, terminated, result


class BrowserMedium(ToolMedium):
    def make_tools(self, circle: Circle) -> list[dict[str, Any]]:
        tools = super().make_tools(circle)
        tools.insert(
            0,
            {
                "name": "browser",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "action": {"type": "string"},
                        "url": {"type": "string"},
                        "selector": {"type": "string"},
                        "text": {"type": "string"},
                    },
                    "required": ["action"],
                },
            },
        )
        return tools

    def process_response(
        self,
        *,
        cantrip: Cantrip,
        thread,
        response: CrystalResponse,
        current_turn_id: str,
        circle: Circle,
        depth: int | None,
        runtime,
        require_done_tool: bool,
    ) -> tuple[list[GateCallRecord], bool, Any]:
        observation: list[GateCallRecord] = []
        terminated = False
        result = None

        if response.tool_calls:
            for c in response.tool_calls:
                if c.gate == "browser":
                    action = str(c.args.get("action", "")).strip()
                    if not action:
                        observation.append(
                            GateCallRecord(
                                gate_name="browser",
                                arguments=c.args,
                                is_error=True,
                                content="action is required",
                            )
                        )
                        continue
                    if runtime is None:
                        observation.append(
                            GateCallRecord(
                                gate_name="browser",
                                arguments=c.args,
                                is_error=True,
                                content="browser runtime unavailable",
                            )
                        )
                        continue
                    try:
                        if action == "open":
                            url = str(c.args.get("url") or "")
                            if not url:
                                raise ValueError("url is required")
                            payload = runtime.open(url)
                        elif action == "click":
                            selector = str(c.args.get("selector") or "")
                            if not selector:
                                raise ValueError("selector is required")
                            payload = runtime.click(selector)
                        elif action == "type":
                            selector = str(c.args.get("selector") or "")
                            text = str(c.args.get("text") or "")
                            if not selector:
                                raise ValueError("selector is required")
                            payload = runtime.type(selector, text)
                        elif action == "text":
                            selector = str(c.args.get("selector") or "")
                            if not selector:
                                raise ValueError("selector is required")
                            payload = runtime.text(selector)
                        elif action == "url":
                            payload = runtime.url()
                        elif action == "title":
                            payload = runtime.title()
                        else:
                            raise ValueError(f"unsupported browser action: {action}")
                        observation.append(
                            GateCallRecord(
                                gate_name="browser",
                                arguments=c.args,
                                result=payload,
                            )
                        )
                    except Exception as e:  # noqa: BLE001
                        observation.append(
                            GateCallRecord(
                                gate_name="browser",
                                arguments=c.args,
                                is_error=True,
                                content=str(e),
                            )
                        )
                    continue

                rec = cantrip._execute_gate(
                    thread,
                    c.gate,
                    c.args,
                    parent_turn_id=current_turn_id,
                    circle=circle,
                    depth=depth,
                )
                observation.append(rec)
                if c.gate == "done" and not rec.is_error:
                    terminated = True
                    result = rec.result
                    break
        else:
            if not require_done_tool:
                terminated = True
                result = response.content

        return observation, terminated, result


def medium_for(medium: str | None) -> Medium:
    if medium == "code":
        return CodeMedium()
    if medium == "browser":
        return BrowserMedium()
    return ToolMedium()
