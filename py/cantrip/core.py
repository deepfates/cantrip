from __future__ import annotations

import copy
import json
import re
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class CantripError(Exception):
    pass


@dataclass(frozen=True)
class Call:
    system_prompt: str | None = None
    temperature: float | None = None
    require_done_tool: bool = False
    tool_choice: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)


@dataclass
class Gate:
    name: str
    parameters: dict[str, Any] | None = None
    behavior: str | None = None
    delay_ms: int | None = None
    result: Any = None
    error: str | None = None
    dependencies: dict[str, Any] | None = None
    ephemeral: bool = False


@dataclass
class Circle:
    gates: list[Any]
    wards: list[dict[str, Any]]
    circle_type: str = "tool"
    filesystem: dict[str, str] | None = None

    def __post_init__(self) -> None:
        self._gates: dict[str, Gate] = {}
        for g in self.gates:
            if isinstance(g, str):
                self._gates[g] = Gate(name=g)
            else:
                self._gates[g["name"]] = Gate(
                    name=g["name"],
                    parameters=g.get("parameters"),
                    behavior=g.get("behavior"),
                    delay_ms=g.get("delay_ms"),
                    result=g.get("result"),
                    error=g.get("error"),
                    dependencies=g.get("dependencies"),
                    ephemeral=bool(g.get("ephemeral", False)),
                )

    def max_turns(self) -> int | None:
        for w in self.wards:
            if "max_turns" in w:
                return int(w["max_turns"])
        return None

    def max_depth(self) -> int | None:
        for w in self.wards:
            if "max_depth" in w:
                return int(w["max_depth"])
        return None

    def removed_gates(self) -> set[str]:
        removed = set()
        for w in self.wards:
            if "remove_gate" in w:
                removed.add(str(w["remove_gate"]))
        return removed

    def available_gates(self) -> dict[str, Gate]:
        removed = self.removed_gates()
        gates = {k: v for k, v in self._gates.items() if k not in removed}
        max_depth = self.max_depth()
        if max_depth is not None and max_depth <= 0:
            gates.pop("call_agent", None)
            gates.pop("call_agent_batch", None)
        return gates


@dataclass
class ToolCall:
    id: str
    gate: str
    args: dict[str, Any]


@dataclass
class CrystalResponse:
    content: str | None = None
    tool_calls: list[ToolCall] | None = None
    usage: dict[str, int] | None = None


@dataclass
class GateCallRecord:
    gate_name: str
    arguments: dict[str, Any]
    result: Any = None
    is_error: bool = False
    content: str = ""
    ephemeral: bool = False


@dataclass
class Turn:
    id: str
    entity_id: str
    sequence: int
    parent_id: str | None
    utterance: dict[str, Any]
    observation: list[GateCallRecord]
    terminated: bool = False
    truncated: bool = False
    reward: float | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class Thread:
    id: str
    entity_id: str
    intent: str
    call: Call
    turns: list[Turn] = field(default_factory=list)
    result: Any = None
    terminated: bool = False
    truncated: bool = False
    cumulative_usage: dict[str, int] = field(
        default_factory=lambda: {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
    )


class Loom:
    def __init__(self) -> None:
        self.threads: list[Thread] = []
        self.turns: list[Turn] = []

    def append_turn(self, thread: Thread, turn: Turn) -> None:
        thread.turns.append(turn)
        self.turns.append(turn)

    def delete_turn(self, _idx: int) -> None:
        raise CantripError("loom is append-only")

    def annotate_reward(self, thread: Thread, index: int, reward: float) -> None:
        thread.turns[index].reward = reward

    def extract_thread(self, thread: Thread) -> list[dict[str, Any]]:
        return [
            {
                "utterance": t.utterance,
                "observation": [r.__dict__ for r in t.observation],
                "terminated": t.terminated,
                "truncated": t.truncated,
            }
            for t in thread.turns
        ]


class FakeCrystal:
    def __init__(self, spec: dict[str, Any] | None = None):
        spec = spec or {}
        self.spec = spec
        self.responses = copy.deepcopy(spec.get("responses", []))
        self.index = 0
        self.record_inputs = bool(spec.get("record_inputs", False))
        self.invocations: list[dict[str, Any]] = []
        self.default_usage = spec.get("usage")
        self.provider = spec.get("provider")
        self.raw_response = spec.get("raw_response")

    def _next_raw(self) -> dict[str, Any]:
        if self.provider == "mock_openai" and self.raw_response:
            return copy.deepcopy(self.raw_response)
        if self.index >= len(self.responses):
            return {"content": ""}
        item = copy.deepcopy(self.responses[self.index])
        self.index += 1
        return item

    def query(self, messages: list[dict[str, Any]], tools: list[dict[str, Any]], tool_choice: str | None) -> CrystalResponse:
        self.invocations.append(
            {
                "messages": copy.deepcopy(messages),
                "tools": copy.deepcopy(tools),
                "tool_choice": tool_choice,
            }
        )

        raw = self._next_raw()

        if "error" in raw:
            err = raw["error"]
            raise CantripError(f"provider_error:{err.get('status')}:{err.get('message')}")

        if self.provider == "mock_openai" and self.raw_response:
            choice = raw["choices"][0]
            msg = choice["message"]
            usage = raw.get("usage", {})
            return CrystalResponse(
                content=msg.get("content"),
                tool_calls=[],
                usage={
                    "prompt_tokens": int(usage.get("prompt_tokens", 0)),
                    "completion_tokens": int(usage.get("completion_tokens", 0)),
                },
            )

        calls = None
        if raw.get("tool_calls") is not None:
            calls = []
            for i, c in enumerate(raw.get("tool_calls", [])):
                calls.append(
                    ToolCall(
                        id=c.get("id") or f"call_{i+1}",
                        gate=c.get("gate") or c.get("name"),
                        args=copy.deepcopy(c.get("args", {})),
                    )
                )

        usage = raw.get("usage") or self.default_usage
        content = raw.get("content")
        if content is None and raw.get("code") is not None:
            content = raw.get("code")
        return CrystalResponse(content=content, tool_calls=calls, usage=usage)


class MiniCodeRuntime:
    def __init__(self) -> None:
        self.env: dict[str, Any] = {}

    def _strip_comments(self, src: str) -> str:
        lines = []
        for ln in src.splitlines():
            if "//" in ln:
                ln = ln.split("//", 1)[0]
            lines.append(ln)
        return "\n".join(lines)

    def _js_to_json(self, text: str) -> str:
        s = text.strip()
        s = re.sub(r"'", '"', s)
        s = re.sub(r"([\{,]\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*:)", r'\1"\2"\3', s)
        return s

    def _eval_expr(self, expr: str, call_gate) -> Any:
        expr = expr.strip().rstrip(";")

        if expr.endswith(".join(\",\")"):
            arr_name = expr[: -len('.join(",")')]
            return ",".join(str(x) for x in self.env.get(arr_name, []))

        if expr.startswith("call_agent_batch("):
            inner = expr[len("call_agent_batch(") : -1]
            reqs = json.loads(self._js_to_json(inner))
            return call_gate("call_agent_batch", reqs)

        if expr.startswith("call_agent("):
            inner = expr[len("call_agent(") : -1]
            req = json.loads(self._js_to_json(inner))
            return call_gate("call_agent", req)

        if expr.startswith("done("):
            inner = expr[len("done(") : -1]
            return call_gate("done", {"answer": self._eval_expr(inner, call_gate)})

        if "+" in expr:
            parts = [p.strip() for p in expr.split("+")]
            out = []
            for p in parts:
                if p == "e.message":
                    out.append(str(self.env.get("e", {}).get("message", "")))
                else:
                    out.append(str(self._eval_expr(p, call_gate)))
            return "".join(out)

        if re.fullmatch(r"-?\d+", expr):
            return int(expr)

        if (expr.startswith('"') and expr.endswith('"')) or (expr.startswith("'") and expr.endswith("'")):
            return expr[1:-1]

        if expr in self.env:
            return self.env[expr]

        raise NameError(expr)

    def execute(self, source: str, call_gate) -> tuple[list[GateCallRecord], Any, bool]:
        code = self._strip_comments(source).strip()
        obs: list[GateCallRecord] = []
        result = None
        done = False

        def invoke_gate(name: str, args: Any) -> Any:
            nonlocal result, done
            rec = call_gate(name, args)
            obs.append(rec)
            if name == "done" and not rec.is_error:
                result = rec.result
                done = True
            if rec.is_error:
                raise CantripError(rec.content)
            return rec.result

        # try/catch block (single-level used in tests)
        if code.startswith("try"):
            m = re.match(r"try\s*\{(.*?)\}\s*catch\(e\)\s*\{(.*?)\}\s*$", code, flags=re.S)
            if m:
                try_block, catch_block = m.group(1).strip(), m.group(2).strip()
                try:
                    t_obs, t_res, t_done = self.execute(try_block, call_gate=call_gate)
                    obs.extend(t_obs)
                    if t_done:
                        result = t_res
                        done = True
                except Exception as e:  # noqa: BLE001
                    self.env["e"] = {"message": str(e)}
                    c_obs, c_res, c_done = self.execute(catch_block, call_gate=call_gate)
                    obs.extend(c_obs)
                    if c_done:
                        result = c_res
                        done = True
                return obs, result, done

        stmts = []
        buf = []
        depth = 0
        quote = None
        for ch in code:
            if quote:
                buf.append(ch)
                if ch == quote:
                    quote = None
                continue
            if ch in {"'", '"'}:
                quote = ch
                buf.append(ch)
                continue
            if ch in "{[(":
                depth += 1
                buf.append(ch)
                continue
            if ch in "}])":
                depth = max(0, depth - 1)
                buf.append(ch)
                continue
            if ch == ";" and depth == 0:
                text = "".join(buf).strip()
                if text:
                    stmts.append(text)
                buf = []
                continue
            buf.append(ch)
        tail = "".join(buf).strip()
        if tail:
            stmts.append(tail)

        for stmt in stmts:
            if stmt.startswith("throw new Error("):
                msg = stmt[len("throw new Error(") : -1]
                raise CantripError(self._eval_expr(msg, invoke_gate))

            m = re.match(r"var\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", stmt, flags=re.S)
            if m:
                name, expr = m.group(1), m.group(2)
                self.env[name] = self._eval_expr(expr, invoke_gate)
                continue

            m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", stmt, flags=re.S)
            if m:
                name, expr = m.group(1), m.group(2)
                self.env[name] = self._eval_expr(expr, invoke_gate)
                continue

            self._eval_expr(stmt, invoke_gate)

        return obs, result, done


class Cantrip:
    def __init__(
        self,
        crystal: FakeCrystal,
        circle: Circle,
        call: Call | None = None,
        *,
        folding: dict[str, Any] | None = None,
        retry: dict[str, Any] | None = None,
        crystals: dict[str, FakeCrystal] | None = None,
        child_crystal: FakeCrystal | None = None,
    ) -> None:
        if crystal is None:
            raise CantripError("cantrip requires a crystal")
        if circle is None:
            raise CantripError("cantrip requires a circle")
        self.crystal = crystal
        self.circle = circle
        self.call = call or Call()
        self.folding = folding or {}
        self.retry = retry or {}
        self.loom = Loom()
        self.crystals = crystals or {}
        self.child_crystal = child_crystal

        if self.call.require_done_tool and "done" not in self.circle._gates:
            raise CantripError("cantrip with require_done must have a done gate")
        if "done" not in self.circle._gates:
            raise CantripError("circle must have a done gate")
        if self.circle.max_turns() is None:
            raise CantripError("cantrip must have at least one truncation ward")

    def _make_tools(self, circle: Circle) -> list[dict[str, Any]]:
        out = []
        for name, gate in circle.available_gates().items():
            out.append({"name": name, "parameters": gate.parameters or {"type": "object"}})
        return out

    def _context_messages(self, thread: Thread) -> list[dict[str, Any]]:
        msgs: list[dict[str, Any]] = []
        if thread.call.system_prompt is not None:
            msgs.append({"role": "system", "content": thread.call.system_prompt})
        msgs.append({"role": "user", "content": thread.intent})

        for t in thread.turns:
            utter = t.utterance
            if utter.get("content"):
                msgs.append({"role": "assistant", "content": utter["content"]})
            if utter.get("tool_calls"):
                msgs.append({"role": "assistant", "content": json.dumps(utter["tool_calls"])})

            if t.observation:
                parts = []
                for r in t.observation:
                    if r.ephemeral:
                        parts.append(f"{r.gate_name}:<ephemeral>")
                    elif r.is_error:
                        parts.append(r.content)
                    else:
                        parts.append(str(r.result))
                msgs.append({"role": "tool", "content": "\n".join(parts)})

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
                rest = [{"role": "tool", "content": "[folded context]"}] + rest[-keep_tail:]
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
                return GateCallRecord(gate_name=gate_name, arguments=args, result=answer)

            if gate_name == "echo":
                return GateCallRecord(gate_name=gate_name, arguments=args, result=args.get("text"))

            if gate_name == "slow_gate":
                if gate.delay_ms:
                    time.sleep(gate.delay_ms / 1000)
                return GateCallRecord(gate_name=gate_name, arguments=args, result=gate.result or "completed")

            if gate_name == "failing_gate":
                raise CantripError(gate.error or "gate failed")

            if gate_name == "fetch":
                return GateCallRecord(gate_name=gate_name, arguments=args, result=f"fetched:{args.get('url')}")

            if gate_name == "read":
                root = (gate.dependencies or {}).get("root", "/")
                path = str(args.get("path"))
                full = str(Path(root) / path)
                data = ""
                if circle.filesystem:
                    data = circle.filesystem.get(full, "")
                return GateCallRecord(gate_name=gate_name, arguments=args, result=data)

            if gate_name == "read_ephemeral":
                return GateCallRecord(
                    gate_name=gate_name,
                    arguments=args,
                    result=gate.result,
                    ephemeral=True,
                )

            if gate_name == "call_agent":
                if depth is not None and depth <= 0:
                    raise CantripError("blocked: depth limit")
                req = args if isinstance(args, dict) else {}
                requested_gates = req.get("gates")
                if requested_gates:
                    parent_g = set(circle.available_gates().keys())
                    if not set(requested_gates).issubset(parent_g):
                        raise CantripError("cannot grant gate")
                child_circle = Circle(
                    gates=list(circle.available_gates().keys()),
                    wards=[
                        {"max_turns": circle.max_turns() or 10},
                        {"max_depth": max((depth or 0) - 1, 0)},
                    ],
                    circle_type=circle.circle_type,
                    filesystem=circle.filesystem,
                )
                child_name = req.get("crystal")
                if child_name:
                    child_crystal = self.crystals.get(child_name)
                elif depth is not None and depth >= 2 and "child_crystal_l1" in self.crystals:
                    child_crystal = self.crystals["child_crystal_l1"]
                elif depth is not None and depth == 1 and "child_crystal_l2" in self.crystals:
                    child_crystal = self.crystals["child_crystal_l2"]
                else:
                    child_crystal = self.child_crystal
                child_crystal = child_crystal or self.crystal
                child = Cantrip(
                    crystal=child_crystal,
                    circle=child_circle,
                    call=self.call,
                    folding=self.folding,
                    retry=self.retry,
                    crystals=self.crystals,
                    child_crystal=self.child_crystal,
                )
                child.loom = self.loom
                res, _th = child._cast_internal(
                    intent=req.get("intent"),
                    crystal_override=child_crystal,
                    parent_turn_id=parent_turn_id,
                    depth=max((depth or 0) - 1, 0),
                )
                had_error = any(rec.is_error for t in _th.turns for rec in t.observation)
                if _th.truncated or (_th.result is None and not _th.terminated) or (had_error and res in (None, "")):
                    raise CantripError("child failed")
                return GateCallRecord(gate_name=gate_name, arguments=req, result=res)

            if gate_name == "call_agent_batch":
                out = []
                for req in args:
                    rec = self._execute_gate(
                        thread,
                        "call_agent",
                        req,
                        parent_turn_id=parent_turn_id,
                        circle=circle,
                        depth=depth,
                    )
                    if rec.is_error:
                        raise CantripError(rec.content)
                    out.append(rec.result)
                return GateCallRecord(gate_name=gate_name, arguments={"batch": args}, result=out)

            return GateCallRecord(gate_name=gate_name, arguments=args, result=gate.result)
        except Exception as e:  # noqa: BLE001
            return GateCallRecord(
                gate_name=gate_name,
                arguments=args,
                is_error=True,
                content=str(e),
            )

    def _query_with_retry(self, crystal: FakeCrystal, messages, tools, tool_choice) -> CrystalResponse:
        max_retries = int(self.retry.get("max_retries", 0))
        retryable = set(self.retry.get("retryable_status_codes", []))
        attempts = 0
        while True:
            try:
                return crystal.query(messages, tools, tool_choice)
            except CantripError as e:
                msg = str(e)
                if not msg.startswith("provider_error:"):
                    raise
                parts = msg.split(":", 2)
                status = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else None
                if attempts < max_retries and status in retryable:
                    attempts += 1
                    continue
                raise

    def _cast_internal(
        self,
        *,
        intent: str,
        crystal_override: FakeCrystal | None = None,
        parent_turn_id: str | None = None,
        depth: int | None = None,
    ) -> tuple[Any, Thread]:
        if not intent:
            raise CantripError("intent is required")

        crystal = crystal_override or self.crystal
        entity_id = str(uuid.uuid4())
        thread = Thread(id=str(uuid.uuid4()), entity_id=entity_id, intent=intent, call=self.call)
        self.loom.threads.append(thread)
        runtime = MiniCodeRuntime() if self.circle.circle_type == "code" else None

        max_turns = self.circle.max_turns() or 1
        local_depth = depth if depth is not None else self.circle.max_depth()

        sequence = 0
        last_turn_id_for_entity = parent_turn_id

        while sequence < max_turns:
            sequence += 1
            t0 = time.perf_counter()
            messages = self._context_messages(thread)
            tools = self._make_tools(self.circle)

            response = self._query_with_retry(crystal, messages, tools, self.call.tool_choice)
            if response.content is None and (response.tool_calls is None or len(response.tool_calls) == 0):
                raise CantripError("crystal returned neither content nor tool_calls")

            observation: list[GateCallRecord] = []
            terminated = False
            result = None

            utterance = {
                "content": response.content,
                "tool_calls": [c.__dict__ for c in (response.tool_calls or [])],
            }

            if self.circle.circle_type == "code" and response.content:
                try:
                    obs, code_result, code_done = runtime.execute(  # type: ignore[union-attr]
                        response.content,
                        call_gate=lambda n, a: self._execute_gate(
                            thread,
                            n,
                            a,
                            parent_turn_id=last_turn_id_for_entity,
                            circle=self.circle,
                            depth=local_depth,
                        ),
                    )
                    observation.extend(obs)
                    if code_done:
                        terminated = True
                        result = code_result
                except Exception as e:  # noqa: BLE001
                    observation.append(
                        GateCallRecord(
                            gate_name="code",
                            arguments={"source": response.content},
                            is_error=True,
                            content=str(e),
                        )
                    )
            elif response.tool_calls:
                ids = [c.id for c in response.tool_calls]
                if len(set(ids)) != len(ids):
                    raise CantripError("duplicate tool call ID")

                for c in response.tool_calls:
                    rec = self._execute_gate(
                        thread,
                        c.gate,
                        c.args,
                        parent_turn_id=last_turn_id_for_entity,
                        circle=self.circle,
                        depth=local_depth,
                    )
                    observation.append(rec)
                    if c.gate == "done" and not rec.is_error:
                        terminated = True
                        result = rec.result
                        break
            else:
                if not self.call.require_done_tool:
                    terminated = True
                    result = response.content

            dt_ms = max(1, int((time.perf_counter() - t0) * 1000))
            usage = response.usage or {"prompt_tokens": 0, "completion_tokens": 0}
            p = int(usage.get("prompt_tokens", 0))
            c = int(usage.get("completion_tokens", 0))
            thread.cumulative_usage["prompt_tokens"] += p
            thread.cumulative_usage["completion_tokens"] += c
            thread.cumulative_usage["total_tokens"] += p + c

            turn = Turn(
                id=str(uuid.uuid4()),
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
            self.loom.append_turn(thread, turn)
            last_turn_id_for_entity = turn.id

            if terminated:
                thread.terminated = True
                thread.result = result
                break

        if not thread.terminated:
            if thread.turns:
                thread.turns[-1].truncated = True
            thread.truncated = True

        return thread.result, thread

    def cast(
        self,
        intent: str,
        *,
        crystal_override: FakeCrystal | None = None,
        parent_turn_id: str | None = None,
        depth: int | None = None,
    ) -> Any:
        result, _thread = self._cast_internal(
            intent=intent,
            crystal_override=crystal_override,
            parent_turn_id=parent_turn_id,
            depth=depth,
        )
        return result

    def fork(self, source_thread: Thread, from_turn: int, crystal: FakeCrystal, intent: str) -> tuple[Any, Thread]:
        if from_turn < 0 or from_turn >= len(source_thread.turns):
            raise CantripError("invalid fork point")

        prefix = source_thread.turns[: from_turn + 1]
        fork_thread = Thread(id=str(uuid.uuid4()), entity_id=str(uuid.uuid4()), intent=intent, call=self.call)
        self.loom.threads.append(fork_thread)
        for t in prefix:
            clone = copy.deepcopy(t)
            fork_thread.turns.append(clone)

        result, new_thread = self._cast_internal(intent=intent, crystal_override=crystal)
        return result, new_thread
