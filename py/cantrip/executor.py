from __future__ import annotations

import io
import json
import os
import re
import subprocess
import sys
import tempfile
import textwrap
from dataclasses import dataclass
from typing import Any, Callable


@dataclass
class CodeExecResult:
    observation: list[Any]
    result: Any
    done: bool


class CodeExecutor:
    def execute(
        self, source: str, call_gate: Callable[[str, Any], Any]
    ) -> CodeExecResult:
        raise NotImplementedError


class MiniCodeExecutor(CodeExecutor):
    """Small JS-like interpreter sufficient for spec tests.

    Not an isolation boundary; use SubprocessCodeExecutor in production deployments.
    """

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

        if expr.endswith('.join(",")'):
            arr_name = expr[: -len('.join(",")')]
            return ",".join(str(x) for x in self.env.get(arr_name, []))

        if expr.startswith("call_entity_batch("):
            inner = expr[len("call_entity_batch(") : -1]
            reqs = json.loads(self._js_to_json(inner))
            return call_gate("call_entity_batch", reqs)

        if expr.startswith("call_entity("):
            inner = expr[len("call_entity(") : -1]
            req = json.loads(self._js_to_json(inner))
            return call_gate("call_entity", req)

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

        if (expr.startswith('"') and expr.endswith('"')) or (
            expr.startswith("'") and expr.endswith("'")
        ):
            return expr[1:-1]

        if expr in self.env:
            return self.env[expr]

        raise NameError(expr)

    def execute(self, source: str, call_gate):
        code = self._strip_comments(source).strip()
        obs: list[Any] = []
        result = None
        done = False

        if code.startswith("try"):
            m = re.match(
                r"try\s*\{(.*?)\}\s*catch\(e\)\s*\{(.*?)\}\s*$", code, flags=re.S
            )
            if m:
                try_block, catch_block = m.group(1).strip(), m.group(2).strip()
                try:
                    tr = self.execute(try_block, call_gate)
                    obs.extend(tr.observation)
                    if tr.done:
                        return tr
                except Exception as e:  # noqa: BLE001
                    self.env["e"] = {"message": str(e)}
                    cr = self.execute(catch_block, call_gate)
                    obs.extend(cr.observation)
                    if cr.done:
                        return cr
                return CodeExecResult(obs, result, done)

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
                s = "".join(buf).strip()
                if s:
                    stmts.append(s)
                buf = []
                continue
            buf.append(ch)
        tail = "".join(buf).strip()
        if tail:
            stmts.append(tail)

        def gate(name: str, args: Any):
            nonlocal result, done
            rec = call_gate(name, args)
            obs.append(rec)
            if rec.is_error:
                raise RuntimeError(rec.content)
            if name == "done":
                result = rec.result
                done = True
            return rec.result

        for stmt in stmts:
            if stmt.startswith("throw new Error("):
                msg = stmt[len("throw new Error(") : -1]
                raise RuntimeError(self._eval_expr(msg, gate))

            m = re.match(
                r"var\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", stmt, flags=re.S
            )
            if m:
                self.env[m.group(1)] = self._eval_expr(m.group(2), gate)
                continue

            m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", stmt, flags=re.S)
            if m:
                self.env[m.group(1)] = self._eval_expr(m.group(2), gate)
                continue

            self._eval_expr(stmt, gate)

        return CodeExecResult(obs, result, done)


class SubprocessPythonExecutor(CodeExecutor):
    """Runs Python snippets in a subprocess with timeout and structured output.

    The user code can set a `result` variable for the return value.
    In code-medium flows, termination still requires explicit `done(...)`.
    This executor is intentionally separate from the JS-like mini interpreter.
    """

    def __init__(self, timeout_s: float = 5.0) -> None:
        self.timeout_s = timeout_s
        self._sentinel = "__CANTRIP_EXEC_RESULT__"

    def execute(
        self, source: str, call_gate: Callable[[str, Any], Any]
    ) -> CodeExecResult:
        # Delegation gates are not available in subprocess mode.
        if "call_entity(" in source or "call_entity_batch(" in source:
            raise RuntimeError(
                "delegation gate calls are not available in SubprocessPythonExecutor"
            )

        script = textwrap.dedent(
            f"""
            import json
            _state = {{"done": False, "result": None}}

            def done(answer):
                _state["done"] = True
                _state["result"] = answer
                return answer

            namespace = {{"done": done}}
            output = {{"ok": True, "done": False, "result": None, "error": None}}
            try:
                exec({source!r}, {{}}, namespace)
                output["done"] = bool(_state["done"])
                output["result"] = (
                    _state["result"] if _state["done"] else namespace.get("result")
                )
            except Exception as e:
                output["ok"] = False
                output["error"] = str(e)
            print("{self._sentinel}" + json.dumps(output))
            """
        )
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fp:
            fp.write(script)
            path = fp.name

        try:
            try:
                proc = subprocess.run(
                    [sys.executable, path],
                    capture_output=True,
                    text=True,
                    timeout=self.timeout_s,
                    check=False,
                )
            except subprocess.TimeoutExpired as e:
                raise RuntimeError(
                    f"code execution timed out after {self.timeout_s:.1f}s"
                ) from e
        finally:
            try:
                os.unlink(path)
            except OSError:
                pass
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.strip() or "subprocess execution failed")

        raw_out = io.StringIO(proc.stdout).read()
        payload = None
        for line in reversed(raw_out.splitlines()):
            if line.startswith(self._sentinel):
                body = line[len(self._sentinel) :].strip()
                try:
                    payload = json.loads(body)
                except Exception as e:  # noqa: BLE001
                    raise RuntimeError(f"invalid subprocess output: {e}") from e
                break
        if payload is None:
            try:
                payload = json.loads(raw_out.strip())
            except Exception as e:  # noqa: BLE001
                raise RuntimeError(f"invalid subprocess output: {e}") from e

        if not payload.get("ok"):
            raise RuntimeError(payload.get("error") or "subprocess execution error")
        obs: list[Any] = []
        if payload.get("done"):
            rec = call_gate("done", {"answer": payload.get("result")})
            obs.append(rec)
            if rec.is_error:
                raise RuntimeError(rec.content)
            return CodeExecResult(observation=obs, result=rec.result, done=True)
        return CodeExecResult(
            observation=obs,
            result=payload.get("result"),
            done=False,
        )
