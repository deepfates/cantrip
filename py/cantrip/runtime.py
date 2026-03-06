from __future__ import annotations

import copy
import json
import threading
import time
import uuid
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from cantrip.browser import browser_driver_from_name
from cantrip.code_runner import (
    InProcessPythonRunnerFactory,
    SubprocessPythonRunnerFactory,
    code_runner_from_name,
)
from cantrip.errors import CantripError, ProviderError, ProviderTimeout, ProviderTransportError
from cantrip.entity import Entity
from cantrip.loom import InMemoryLoomStore, Loom
from cantrip.mediums import medium_for
from cantrip.models import Identity, Circle, LLMResponse, GateCallRecord, Thread, Turn
from cantrip.providers.base import LLM
from cantrip.providers.fake import FakeLLM


class Cantrip:
    def __init__(
        self,
        llm: LLM,
        circle: Circle,
        identity: Identity | None = None,
        *,
        folding: dict[str, Any] | None = None,
        retry: dict[str, Any] | None = None,
        llms: dict[str, LLM] | None = None,
        child_llm: LLM | None = None,
        loom: Loom | None = None,
        medium_depends: dict[str, Any] | None = None,
    ) -> None:
        if llm is None:
            raise CantripError("cantrip requires an llm")
        if circle is None:
            raise CantripError("cantrip requires a circle")
        self.llm = llm
        self.circle = circle
        self.identity = identity or Identity()
        self.folding = folding or {}
        self.retry = retry or {}
        self.loom = loom or Loom()
        self.llms = llms or {}
        self.child_llm = child_llm
        self.medium_depends = medium_depends or {}

        if self.identity.require_done_tool and "done" not in self.circle._gates:
            raise CantripError("cantrip with require_done must have a done gate")
        if "done" not in self.circle._gates:
            raise CantripError("circle must have a done gate")
        if self.circle.max_turns() is None:
            raise CantripError("cantrip must have at least one truncation ward")

    def _make_tools(self, circle: Circle) -> list[dict[str, Any]]:
        return medium_for(circle.medium).make_tools(circle)

    def _merged_depends(
        self,
        parent: dict[str, Any] | None,
        override: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        out = dict(parent or {})
        for k, v in (override or {}).items():
            if isinstance(v, dict) and isinstance(out.get(k), dict):
                out[k] = self._merged_depends(out.get(k), v)
            else:
                out[k] = v
        return out

    def _circle_depends(self, circle: Circle) -> dict[str, Any]:
        return self._merged_depends(self.medium_depends, circle.depends)

    def _capability_message(self, circle: Circle) -> str:
        gates = sorted(circle.available_gates().keys())
        gate_list = ", ".join(gates)
        wards = json.dumps(circle.wards, sort_keys=True)
        return (
            "Circle capabilities:\n"
            f"medium={circle.medium}\n"
            f"gates={gate_list}\n"
            f"wards={wards}"
        )

    def _context_messages(self, thread: Thread) -> list[dict[str, Any]]:
        msgs: list[dict[str, Any]] = []
        medium = medium_for(self.circle.medium)
        cap_text = medium.capability_text(self.circle)
        if cap_text is not None:
            msgs.append({"role": "system", "content": cap_text})
        if thread.identity.system_prompt is not None:
            msgs.append({"role": "system", "content": thread.identity.system_prompt})
        if cap_text is None:
            msgs.append(
                {"role": "system", "content": self._capability_message(self.circle)}
            )
        msgs.append({"role": "user", "content": thread.intent})

        for t in thread.turns:
            utter = t.utterance
            raw_tool_calls = utter.get("tool_calls") or []
            if raw_tool_calls:
                tool_calls_payload = []
                for i, call in enumerate(raw_tool_calls):
                    call_id = call.get("id") or f"call_{i+1}"
                    gate_name = call.get("gate")
                    args = call.get("args") or {}
                    tool_calls_payload.append(
                        {
                            "id": call_id,
                            "type": "function",
                            "function": {
                                "name": gate_name,
                                "arguments": json.dumps(args),
                            },
                        }
                    )
                msgs.append(
                    {
                        "role": "assistant",
                        "content": utter.get("content") or "",
                        "tool_calls": tool_calls_payload,
                    }
                )
            elif utter.get("content"):
                msgs.append({"role": "assistant", "content": utter["content"]})

            if t.observation:

                def obs_text(rec: GateCallRecord) -> str:
                    if rec.ephemeral:
                        return f"{rec.gate_name}:<ephemeral>"
                    if rec.is_error:
                        return rec.content
                    return str(rec.result)

                if raw_tool_calls:
                    for i, rec in enumerate(t.observation):
                        tc_id = (
                            raw_tool_calls[i].get("id")
                            if i < len(raw_tool_calls)
                            else None
                        )
                        if tc_id:
                            msgs.append(
                                {
                                    "role": "tool",
                                    "tool_call_id": tc_id,
                                    "content": obs_text(rec),
                                }
                            )
                        else:
                            msgs.append({"role": "user", "content": obs_text(rec)})
                else:
                    msgs.append(
                        {
                            "role": "user",
                            "content": "\n".join(obs_text(r) for r in t.observation),
                        }
                    )

        trigger = self.folding.get("trigger_after_turns")
        if trigger and len(thread.turns) > int(trigger):
            keep_tail = 4
            head = []
            if msgs and msgs[0]["role"] == "system":
                head = [msgs[0]]
                rest = msgs[1:]
            else:
                rest = msgs
            if len(rest) > keep_tail:
                rest = [{"role": "tool", "content": "[folded context]"}] + rest[
                    -keep_tail:
                ]
            msgs = head + rest

        return msgs

    def _execute_gate(
        self,
        thread: Thread,
        gate_name: str,
        args: dict[str, Any],
        *,
        parent_turn_id: str | None,
        circle: Circle,
        depth: int | None,
    ) -> GateCallRecord:
        gates = circle.available_gates()
        if gate_name not in gates:
            return GateCallRecord(
                gate_name=gate_name,
                arguments=args,
                is_error=True,
                content="gate not available",
            )

        gate = gates[gate_name]

        try:
            if gate_name == "done":
                answer = args.get("answer") if isinstance(args, dict) else args
                if answer is None:
                    return GateCallRecord(
                        gate_name=gate_name,
                        arguments=args,
                        is_error=True,
                        content="done requires non-empty answer",
                    )
                answer_text = str(answer).strip()
                if not answer_text:
                    return GateCallRecord(
                        gate_name=gate_name,
                        arguments=args,
                        is_error=True,
                        content="done requires non-empty answer",
                    )
                normalized_answer = answer_text if isinstance(answer, str) else answer
                return GateCallRecord(
                    gate_name=gate_name, arguments=args, result=normalized_answer
                )

            if gate_name == "echo":
                return GateCallRecord(
                    gate_name=gate_name, arguments=args, result=args.get("text")
                )

            if gate_name == "slow_gate":
                if gate.delay_ms:
                    time.sleep(gate.delay_ms / 1000)
                return GateCallRecord(
                    gate_name=gate_name,
                    arguments=args,
                    result=gate.result or "completed",
                )

            if gate_name == "failing_gate":
                raise CantripError(gate.error or "gate failed")

            if gate_name == "fetch":
                return GateCallRecord(
                    gate_name=gate_name,
                    arguments=args,
                    result=f"fetched:{args.get('url')}",
                )

            if gate_name == "read":
                gate_depends = gate.depends or {}
                circle_depends = circle.depends or {}
                root = (
                    gate_depends.get("root")
                    or circle_depends.get("root")
                    or (circle_depends.get("filesystem") or {}).get("root")
                    or "/"
                )
                path = str(args.get("path"))
                full = str(Path(root) / path)
                data = ""
                if circle.filesystem:
                    data = circle.filesystem.get(full, "")
                return GateCallRecord(gate_name=gate_name, arguments=args, result=data)

            if gate_name == "repo_files":
                root = Path((gate.depends or {}).get("root", ".")).resolve()
                pattern = str(args.get("glob", "**/*"))
                limit = int(args.get("limit", 200))
                if limit < 1:
                    limit = 1
                if limit > 2000:
                    limit = 2000

                paths: list[str] = []
                for p in root.glob(pattern):
                    try:
                        resolved = p.resolve()
                    except Exception:  # noqa: BLE001
                        continue
                    if not str(resolved).startswith(str(root)):
                        continue
                    if resolved.is_file():
                        paths.append(resolved.relative_to(root).as_posix())
                paths.sort()
                return GateCallRecord(
                    gate_name=gate_name, arguments=args, result=paths[:limit]
                )

            if gate_name == "repo_read":
                root = Path((gate.depends or {}).get("root", ".")).resolve()
                rel = str(args.get("path", ""))
                if not rel:
                    raise CantripError("path is required")
                target = (root / rel).resolve()
                if not str(target).startswith(str(root)):
                    raise CantripError("path escapes root")
                if not target.exists() or not target.is_file():
                    raise CantripError("file not found")
                max_bytes = int(args.get("max_bytes", 20000))
                if max_bytes < 1:
                    max_bytes = 1
                if max_bytes > 1_000_000:
                    max_bytes = 1_000_000
                raw = target.read_bytes()
                clipped = raw[:max_bytes]
                text = clipped.decode("utf-8", errors="replace")
                if len(raw) > max_bytes:
                    text += "\n...[truncated]"
                return GateCallRecord(gate_name=gate_name, arguments=args, result=text)

            if gate_name == "read_ephemeral":
                return GateCallRecord(
                    gate_name=gate_name,
                    arguments=args,
                    result=gate.result,
                    ephemeral=True,
                )

            if gate_name == "call_entity":
                if depth is not None and depth <= 0:
                    raise CantripError("blocked: depth limit")
                req = args if isinstance(args, dict) else {}
                allowed_req_keys = {
                    "intent",
                    "context",
                    "gates",
                    "wards",
                    "llm",
                    "require_done_tool",
                    "medium",
                    "depends",
                    "system_prompt",
                }
                for k in req.keys():
                    if k not in allowed_req_keys:
                        raise CantripError(f"unknown call_entity arg: {k}")
                # If context is provided, prepend it to the intent so the child sees it.
                if req.get("context") is not None:
                    ctx = req["context"]
                    ctx_str = json.dumps(ctx) if not isinstance(ctx, str) else ctx
                    req = dict(req)
                    req["intent"] = f"Context: {ctx_str}\n\nTask: {req.get('intent', '')}"

                requested_wards = req.get("wards") or []
                if not isinstance(requested_wards, list):
                    requested_wards = []

                parent_max_turns = circle.max_turns()
                requested_max_turns = None
                for w in requested_wards:
                    if isinstance(w, dict) and "max_turns" in w:
                        requested_max_turns = int(w["max_turns"])
                        break
                if parent_max_turns is None:
                    composed_max_turns = requested_max_turns
                elif requested_max_turns is None:
                    composed_max_turns = parent_max_turns
                else:
                    composed_max_turns = min(parent_max_turns, requested_max_turns)
                if composed_max_turns is None:
                    composed_max_turns = 10

                parent_child_depth = max((depth or 0) - 1, 0)
                requested_max_depth = None
                for w in requested_wards:
                    if isinstance(w, dict) and "max_depth" in w:
                        requested_max_depth = int(w["max_depth"])
                        break
                if requested_max_depth is None:
                    composed_max_depth = parent_child_depth
                else:
                    composed_max_depth = min(parent_child_depth, requested_max_depth)

                child_wards: list[dict[str, Any]] = [
                    {"max_turns": composed_max_turns},
                    {"max_depth": composed_max_depth},
                ]

                available_parent_gates = circle.available_gates()
                if isinstance(req.get("gates"), list) and req.get("gates"):
                    gate_names = list(dict.fromkeys([*req["gates"], "done"]))
                else:
                    gate_names = list(available_parent_gates.keys())

                child_gates = []
                for name in gate_names:
                    parent_gate = available_parent_gates.get(name)
                    if parent_gate is None:
                        child_gates.append({"name": name})
                        continue
                    child_gates.append(
                        {
                            "name": name,
                            "parameters": copy.deepcopy(parent_gate.parameters),
                            "behavior": parent_gate.behavior,
                            "delay_ms": parent_gate.delay_ms,
                            "result": copy.deepcopy(parent_gate.result),
                            "error": parent_gate.error,
                            "depends": copy.deepcopy(parent_gate.depends),
                            "ephemeral": bool(parent_gate.ephemeral),
                        }
                    )

                child_medium = req.get("medium")
                child_circle_medium = (
                    str(child_medium) if child_medium is not None else circle.medium
                )

                child_circle = Circle(
                    gates=child_gates,
                    wards=child_wards,
                    medium=child_circle_medium,
                    depends=self._merged_depends(
                        circle.depends,
                        req.get("depends")
                        if isinstance(req.get("depends"), dict)
                        else None,
                    ),
                    filesystem=circle.filesystem,
                )

                child_name = req.get("llm")
                if child_name:
                    child_llm = self.llms.get(child_name)
                elif (
                    depth is not None
                    and depth >= 2
                    and "child_llm_l1" in self.llms
                ):
                    child_llm = self.llms["child_llm_l1"]
                elif (
                    depth is not None
                    and depth == 1
                    and "child_llm_l2" in self.llms
                ):
                    child_llm = self.llms["child_llm_l2"]
                else:
                    child_llm = self.child_llm

                child_llm = child_llm or self.llm
                # Use request's system_prompt if provided; otherwise give children
                # a generic prompt so they don't inherit parent's delegation instructions
                # (which reference gates unavailable at lower depths).
                child_system_prompt = req.get("system_prompt") or (
                    "You are a helpful assistant. Complete the task and return your answer. "
                    "If you have a code tool, write Python code that calls done(answer) with the result. "
                    "If you have a done tool, call done with your answer."
                )
                child_call = Identity(
                    system_prompt=child_system_prompt,
                    temperature=self.identity.temperature,
                    require_done_tool=self.identity.require_done_tool
                    or bool(req.get("require_done_tool", False)),
                    tool_choice=self.identity.tool_choice,
                    extra=copy.deepcopy(self.identity.extra),
                )
                child = Cantrip(
                    llm=child_llm,
                    circle=child_circle,
                    identity=child_call,
                    folding=self.folding,
                    retry=self.retry,
                    llms=self.llms,
                    child_llm=self.child_llm,
                    loom=self.loom,
                    medium_depends=self.medium_depends,
                )
                res, ch_thread = child._cast_internal(
                    intent=req.get("intent"),
                    llm_override=child_llm,
                    parent_turn_id=parent_turn_id,
                    depth=max((depth or 0) - 1, 0),
                )
                had_error = any(
                    rec.is_error for t in ch_thread.turns for rec in t.observation
                )
                if (
                    ch_thread.truncated
                    or (ch_thread.result is None and not ch_thread.terminated)
                    or (had_error and res in (None, ""))
                ):
                    raise CantripError("child failed")
                return GateCallRecord(gate_name=gate_name, arguments=req, result=res)

            if gate_name == "call_entity_batch":
                if not isinstance(args, list):
                    raise CantripError("invalid batch args")
                if len(args) > 50:
                    raise CantripError("batch too large")

                created_fake_llms: list[str] = []
                if isinstance(self.child_llm, FakeLLM):
                    base_spec = copy.deepcopy(self.child_llm.spec)
                    base_responses = copy.deepcopy(self.child_llm.responses)
                    for i, req in enumerate(args):
                        if not isinstance(req, dict):
                            continue
                        if req.get("llm"):
                            continue
                        spec_i = copy.deepcopy(base_spec)
                        if i < len(base_responses):
                            spec_i["responses"] = [base_responses[i]]
                        else:
                            spec_i["responses"] = [{"content": ""}]
                        key = f"__batch_fake_child_{id(thread)}_{i}"
                        self.llms[key] = FakeLLM(spec_i)
                        req["llm"] = key
                        created_fake_llms.append(key)

                def run_child(req: dict[str, Any]) -> GateCallRecord:
                    return self._execute_gate(
                        thread,
                        "call_entity",
                        req,
                        parent_turn_id=parent_turn_id,
                        circle=circle,
                        depth=depth,
                    )

                out = []
                try:
                    if len(args) > 1 and isinstance(self.loom.store, InMemoryLoomStore):
                        workers = min(8, len(args))
                        with ThreadPoolExecutor(max_workers=workers) as pool:
                            recs = list(pool.map(run_child, args))
                        for rec in recs:
                            if rec.is_error:
                                raise CantripError(rec.content)
                            out.append(rec.result)
                    else:
                        for req in args:
                            rec = run_child(req)
                            if rec.is_error:
                                raise CantripError(rec.content)
                            out.append(rec.result)
                finally:
                    for key in created_fake_llms:
                        self.llms.pop(key, None)
                return GateCallRecord(
                    gate_name=gate_name, arguments={"batch": args}, result=out
                )

            return GateCallRecord(
                gate_name=gate_name, arguments=args, result=gate.result
            )
        except Exception as e:  # noqa: BLE001
            return GateCallRecord(
                gate_name=gate_name, arguments=args, is_error=True, content=str(e)
            )

    def _query_with_retry(
        self,
        llm: LLM,
        messages,
        tools,
        tool_choice,
        *,
        cancel_check: Callable[[], bool] | None = None,
    ) -> LLMResponse:
        max_retries = int(self.retry.get("max_retries", 0))
        retryable = set(self.retry.get("retryable_status_codes", []))
        attempts = 0

        def _query_once() -> LLMResponse:
            if cancel_check is None:
                return llm.query(messages, tools, tool_choice)
            result_holder: dict[str, Any] = {}
            error_holder: dict[str, BaseException] = {}

            def _worker() -> None:
                try:
                    result_holder["response"] = llm.query(
                        messages, tools, tool_choice
                    )
                except BaseException as e:  # noqa: BLE001
                    error_holder["error"] = e

            t = threading.Thread(target=_worker, daemon=True)
            t.start()
            while t.is_alive():
                if cancel_check():
                    raise CantripError("cancelled")
                t.join(timeout=0.05)
            if "error" in error_holder:
                raise error_holder["error"]
            return result_holder["response"]

        while True:
            try:
                if cancel_check is not None and cancel_check():
                    raise CantripError("cancelled")
                return _query_once()
            except (ProviderTimeout, ProviderTransportError):
                if attempts < max_retries:
                    attempts += 1
                    continue
                raise
            except ProviderError as e:
                if attempts < max_retries and e.status_code in retryable:
                    attempts += 1
                    continue
                raise

    def _truncate_active_children_for_parent(self, parent_thread: Thread) -> None:
        parent_turn_ids = {t.id for t in parent_thread.turns}
        if not parent_turn_ids:
            return

        child_entity_ids = {
            t.entity_id for t in self.loom.turns if t.parent_id in parent_turn_ids
        }
        if not child_entity_ids:
            return

        for thread in self.loom.list_threads():
            if thread.entity_id not in child_entity_ids:
                continue
            if thread.terminated or thread.truncated:
                continue

            thread.truncated = True
            if thread.turns:
                last = thread.turns[-1]
                last.truncated = True
                last.metadata = dict(last.metadata)
                last.metadata["truncation_reason"] = "parent_terminated"
            self.loom.update_thread(thread)

    def _cast_internal(
        self,
        *,
        intent: str,
        llm_override: LLM | None = None,
        parent_turn_id: str | None = None,
        depth: int | None = None,
        seed_turns: list[Turn] | None = None,
        event_sink: Callable[[dict[str, Any]], None] | None = None,
        cancel_check: Callable[[], bool] | None = None,
    ) -> tuple[Any, Thread]:
        if not intent:
            raise CantripError("intent is required")

        llm = llm_override or self.llm
        entity_id = str(uuid.uuid4())
        thread = Thread(
            id=str(uuid.uuid4()), entity_id=entity_id, intent=intent, identity=self.identity
        )
        if seed_turns:
            thread.turns.extend(copy.deepcopy(seed_turns))
        self.loom.register_thread(thread)
        runtime = None
        circle_deps = self._circle_depends(self.circle)
        if self.circle.medium == "code":
            code_dep = circle_deps.get("code") if isinstance(circle_deps, dict) else {}
            if isinstance(code_dep, dict) and code_dep.get("executor") is not None:
                runtime = code_dep.get("executor")
            else:
                runner = (
                    code_dep.get("runner")
                    if isinstance(code_dep, dict) and code_dep.get("runner")
                    else "inprocess"
                )
                timeout_s = (
                    float(code_dep.get("timeout_s"))
                    if isinstance(code_dep, dict) and code_dep.get("timeout_s") is not None
                    else None
                )
                if (
                    str(runner) in {"python-subprocess", "subprocess-python", "python"}
                    and timeout_s is not None
                ):
                    runtime = SubprocessPythonRunnerFactory(
                        timeout_s=timeout_s
                    ).create_executor()
                elif (
                    str(runner) in {"inprocess", "inprocess-python", "python-inprocess"}
                    and timeout_s is not None
                ):
                    runtime = InProcessPythonRunnerFactory(
                        timeout_s=timeout_s
                    ).create_executor()
                else:
                    runtime = code_runner_from_name(str(runner)).create_executor()
        elif self.circle.medium == "browser":
            browser_dep = (
                circle_deps.get("browser") if isinstance(circle_deps, dict) else {}
            )
            if (
                isinstance(browser_dep, dict)
                and browser_dep.get("session_factory") is not None
            ):
                session_factory = browser_dep.get("session_factory")
                runtime = session_factory.create_session()
            else:
                driver = (
                    browser_dep.get("driver")
                    if isinstance(browser_dep, dict) and browser_dep.get("driver")
                    else "memory"
                )
                runtime = browser_driver_from_name(str(driver)).create_session()
        medium = medium_for(self.circle.medium)

        max_turns = self.circle.max_turns() or 1
        local_depth = depth if depth is not None else self.circle.max_depth()

        sequence = len(thread.turns)
        last_turn_id_for_entity = parent_turn_id or (
            thread.turns[-1].id if thread.turns else None
        )
        stagnant_code_turns = 0
        truncation_reason: str | None = None

        while sequence < max_turns:
            if cancel_check is not None and cancel_check():
                thread.truncated = True
                thread.__dict__["cancelled"] = True
                if thread.turns:
                    thread.turns[-1].truncated = True
                    thread.turns[-1].metadata = dict(thread.turns[-1].metadata)
                    thread.turns[-1].metadata["truncation_reason"] = "cancelled"
                break
            sequence += 1
            t0 = time.perf_counter()
            current_turn_id = str(uuid.uuid4())
            if event_sink is not None:
                event_sink(
                    {
                        "type": "step_start",
                        "turn_id": current_turn_id,
                        "sequence": sequence,
                    }
                )
            messages = self._context_messages(thread)
            tools = self._make_tools(self.circle)
            tool_choice = medium.tool_choice(self.identity.tool_choice)
            if self.identity.require_done_tool and tool_choice is None:
                tool_choice = "required"

            try:
                response = self._query_with_retry(
                    llm,
                    messages,
                    tools,
                    tool_choice,
                    cancel_check=cancel_check,
                )
            except CantripError as e:
                if str(e) == "cancelled":
                    thread.truncated = True
                    thread.__dict__["cancelled"] = True
                    if thread.turns:
                        thread.turns[-1].truncated = True
                        thread.turns[-1].metadata = dict(thread.turns[-1].metadata)
                        thread.turns[-1].metadata["truncation_reason"] = "cancelled"
                    break
                raise
            if response.content is None and (
                response.tool_calls is None or len(response.tool_calls) == 0
            ):
                raise CantripError("llm returned neither content nor tool_calls")

            observation: list[GateCallRecord] = []
            terminated = False
            result = None

            utterance = {
                "content": response.content,
                "tool_calls": [c.__dict__ for c in (response.tool_calls or [])],
            }
            if event_sink is not None and utterance.get("content"):
                event_sink(
                    {
                        "type": "text",
                        "turn_id": current_turn_id,
                        "content": utterance["content"],
                    }
                )

            observation, terminated, result = medium.process_response(
                cantrip=self,
                thread=thread,
                response=response,
                current_turn_id=current_turn_id,
                circle=self.circle,
                depth=local_depth,
                runtime=runtime,
                require_done_tool=self.identity.require_done_tool,
            )

            if (
                self.circle.medium == "code"
                and self.identity.require_done_tool
                and not terminated
                and (
                    (
                        observation
                        and all(
                            (not rec.is_error)
                            and rec.gate_name == "code"
                            and (rec.result in {"", None})
                            and not rec.content
                            for rec in observation
                        )
                    )
                    or (not observation and response.content is not None)
                )
            ):
                stagnant_code_turns += 1
            else:
                stagnant_code_turns = 0

            # Guard against non-terminal code loops that generate no progress.
            if not terminated and stagnant_code_turns >= 4:
                observation.append(
                    GateCallRecord(
                        gate_name="code",
                        arguments={"reason": "stagnation_guard"},
                        is_error=True,
                        content="non-terminal code loop detected",
                    )
                )
                truncation_reason = "stagnation_guard"
            if event_sink is not None:
                for rec in observation:
                    event_sink(
                        {
                            "type": "tool_result",
                            "turn_id": current_turn_id,
                            "gate": rec.gate_name,
                            "arguments": rec.arguments,
                            "is_error": rec.is_error,
                            "result": rec.result,
                            "content": rec.content,
                        }
                    )

            # Fail fast when a turn only emits unavailable-gate errors.
            # This avoids spinning through max_turns with no actionable progress.
            if (
                not terminated
                and truncation_reason is None
                and observation
                and all(
                    rec.is_error and rec.content == "gate not available"
                    for rec in observation
                )
            ):
                truncation_reason = "gate_not_available"

            dt_ms = max(1, int((time.perf_counter() - t0) * 1000))
            usage = response.usage or {"prompt_tokens": 0, "completion_tokens": 0}
            p = int(usage.get("prompt_tokens", 0))
            c = int(usage.get("completion_tokens", 0))
            thread.cumulative_usage["prompt_tokens"] += p
            thread.cumulative_usage["completion_tokens"] += c
            thread.cumulative_usage["total_tokens"] += p + c

            turn = Turn(
                id=current_turn_id,
                entity_id=entity_id,
                sequence=sequence,
                parent_id=last_turn_id_for_entity,
                utterance=utterance,
                observation=observation,
                terminated=terminated,
                truncated=False,
                metadata={
                    "tokens_prompt": p,
                    "tokens_completion": c,
                    "duration_ms": dt_ms,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                },
            )
            provider_ms = usage.get("provider_latency_ms")
            if provider_ms is not None:
                try:
                    turn.metadata["provider_latency_ms"] = int(provider_ms)
                except Exception:  # noqa: BLE001
                    pass
            self.loom.append_turn(thread, turn)
            last_turn_id_for_entity = turn.id
            if event_sink is not None:
                event_sink(
                    {
                        "type": "step_complete",
                        "turn_id": current_turn_id,
                        "sequence": sequence,
                    }
                )

            if terminated:
                thread.terminated = True
                thread.result = result
                break
            if truncation_reason is not None:
                break

        if not thread.terminated:
            was_cancelled = bool(thread.__dict__.get("cancelled"))
            if thread.turns:
                thread.turns[-1].truncated = True
                thread.turns[-1].metadata = dict(thread.turns[-1].metadata)
                if not was_cancelled:
                    thread.turns[-1].metadata["truncation_reason"] = (
                        truncation_reason or "max_turns"
                    )
            thread.truncated = True
        if self.circle.medium == "browser" and runtime is not None:
            try:
                runtime.close()
            except Exception:  # noqa: BLE001
                pass
        self._truncate_active_children_for_parent(thread)

        self.loom.update_thread(thread)
        if event_sink is not None:
            event_sink(
                {
                    "type": "final_response",
                    "thread_id": thread.id,
                    "result": thread.result,
                }
            )
        return thread.result, thread

    def cast(
        self,
        intent: str,
        *,
        llm_override: LLM | None = None,
        parent_turn_id: str | None = None,
        depth: int | None = None,
    ) -> Any:
        result, _thread = self._cast_internal(
            intent=intent,
            llm_override=llm_override,
            parent_turn_id=parent_turn_id,
            depth=depth,
        )
        return result

    def summon(self) -> "Entity":
        """Create a persistent entity. Use entity.send(intent) to run intents."""
        return Entity(self)

    def cast_stream(
        self,
        intent: str,
        *,
        llm_override: LLM | None = None,
        parent_turn_id: str | None = None,
        depth: int | None = None,
    ):
        """Yield a simple event stream for one cast."""
        stream_events: list[dict[str, Any]] = []
        self._cast_internal(
            intent=intent,
            llm_override=llm_override,
            parent_turn_id=parent_turn_id,
            depth=depth,
            event_sink=stream_events.append,
        )
        for event in stream_events:
            yield event

    def cast_with_thread(
        self,
        intent: str,
        *,
        llm_override: LLM | None = None,
        parent_turn_id: str | None = None,
        depth: int | None = None,
        seed_turns: list[Turn] | None = None,
        event_sink: Callable[[dict[str, Any]], None] | None = None,
        cancel_check: Callable[[], bool] | None = None,
    ) -> tuple[Any, Thread]:
        """Public helper for protocol adapters that need thread metadata."""
        return self._cast_internal(
            intent=intent,
            llm_override=llm_override,
            parent_turn_id=parent_turn_id,
            depth=depth,
            seed_turns=seed_turns,
            event_sink=event_sink,
            cancel_check=cancel_check,
        )

    def fork(
        self, source_thread: Thread, from_turn: int, llm: LLM, intent: str
    ) -> tuple[Any, Thread]:
        if from_turn < 0 or from_turn >= len(source_thread.turns):
            raise CantripError("invalid fork point")

        prefix = source_thread.turns[: from_turn + 1]
        result, new_thread = self._cast_internal(
            intent=intent, llm_override=llm, seed_turns=prefix
        )
        return result, new_thread
