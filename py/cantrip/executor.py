from __future__ import annotations

import io
import json
import os
import re
import subprocess
import sys
import tempfile
import textwrap
import threading
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


# Builtins ward for InProcessPythonExecutor.
# Per the spec, wards are subtractive: start with everything, remove what's
# dangerous.  This set is subtracted from Python's full builtins.
_BUILTIN_WARDS: set[str] = {
    "__import__",   # module loading — primary host-escape vector
    "open",         # filesystem access
    "eval",         # code evaluation (entity already has exec via the medium)
    "exec",         # code execution
    "compile",      # code compilation
    "input",        # stdin access
    "breakpoint",   # debugger
    "exit",         # process termination
    "quit",         # process termination
    "help",         # interactive help (blocks on stdin)
    "globals",      # frame introspection
    "locals",       # frame introspection
    "vars",         # frame introspection
    "copyright",    # interactive repl artifact
    "credits",      # interactive repl artifact
    "license",      # interactive repl artifact
}
_raw_builtins: dict[str, Any] = (
    __builtins__ if isinstance(__builtins__, dict)  # type: ignore[union-attr]
    else {k: getattr(__builtins__, k) for k in dir(__builtins__)}
)
_WARDED_BUILTINS: dict[str, Any] = {
    k: v for k, v in _raw_builtins.items() if k not in _BUILTIN_WARDS
}


class _DoneSignal(Exception):
    """Internal signal raised when done() is called to stop execution."""

    pass


class InProcessPythonExecutor(CodeExecutor):
    """Runs entity-written Python via exec() with gate functions injected.

    Not a security boundary — builtins are warded (see _BUILTIN_WARDS) but
    CPython exec() is escapable via subclass traversal.  For process-level
    isolation use SubprocessPythonExecutor (which trades away delegation gates).

    Available functions in entity code: done(answer), call_entity(req_dict),
    call_entity_batch(req_list), call_gate(name, args).  Variables persist
    across turns via self.env.

    Timeout is best-effort: on expiry the turn stops but the background thread
    may continue until process exit (CPython threads cannot be killed).
    """

    def __init__(self, timeout_s: float = 5.0) -> None:
        self.env: dict[str, Any] = {}
        self.timeout_s = timeout_s

    def execute(
        self, source: str, call_gate: Callable[[str, Any], Any]
    ) -> CodeExecResult:
        obs: list[Any] = []
        result = None
        is_done = False

        def done(answer: Any) -> Any:
            nonlocal result, is_done
            rec = call_gate("done", {"answer": answer})
            obs.append(rec)
            if rec.is_error:
                raise RuntimeError(rec.content)
            result = rec.result
            is_done = True
            raise _DoneSignal()

        def call_entity(req: dict[str, Any]) -> Any:
            rec = call_gate("call_entity", req)
            obs.append(rec)
            if rec.is_error:
                raise RuntimeError(rec.content)
            return rec.result

        def call_entity_batch(reqs: list[dict[str, Any]]) -> Any:
            rec = call_gate("call_entity_batch", reqs)
            obs.append(rec)
            if rec.is_error:
                raise RuntimeError(rec.content)
            return rec.result

        # Capture print() output
        captured_print = io.StringIO()

        def safe_print(*args: Any, **kwargs: Any) -> None:
            kwargs.pop("file", None)
            print(*args, file=captured_print, **kwargs)

        def _call_gate(gate_name: str, arguments: Any = None) -> Any:
            rec = call_gate(gate_name, arguments or {})
            obs.append(rec)
            if rec.is_error:
                raise RuntimeError(rec.content)
            return rec.result

        namespace: dict[str, Any] = {
            **self.env,
            "done": done,
            "call_entity": call_entity,
            "call_entity_batch": call_entity_batch,
            "call_gate": _call_gate,
            "print": safe_print,
        }

        warded_builtins = dict(_WARDED_BUILTINS)
        warded_builtins["print"] = safe_print
        namespace["__builtins__"] = warded_builtins

        error_holder: dict[str, BaseException] = {}
        finished = threading.Event()

        def _run() -> None:
            try:
                exec(source, namespace)  # noqa: S102
            except _DoneSignal:
                pass
            except BaseException as e:  # noqa: BLE001
                error_holder["error"] = e
            finally:
                finished.set()

        thread = threading.Thread(target=_run, daemon=True)
        thread.start()
        thread.join(timeout=self.timeout_s)

        if not finished.is_set():
            raise RuntimeError(
                f"code execution timed out after {self.timeout_s:.1f}s"
            )

        if "error" in error_holder:
            raise error_holder["error"]  # type: ignore[misc]

        # Persist variables for next turn (exclude injected functions)
        _injected = {"done", "call_entity", "call_entity_batch", "call_gate", "print", "__builtins__"}
        for k, v in namespace.items():
            if k not in _injected:
                self.env[k] = v

        return CodeExecResult(observation=obs, result=result, done=is_done)


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
