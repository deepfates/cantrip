from __future__ import annotations

import pytest

from cantrip.executor import MiniCodeExecutor, SubprocessPythonExecutor
from cantrip.models import GateCallRecord


def test_subprocess_python_executor_returns_result() -> None:
    ex = SubprocessPythonExecutor(timeout_s=2.0)
    out = ex.execute("result = 6 * 7", call_gate=lambda _n, _a: None)
    assert out.done is False
    assert out.result == 42


def test_subprocess_python_executor_supports_done_call() -> None:
    ex = SubprocessPythonExecutor(timeout_s=2.0)
    out = ex.execute(
        "done('ok')",
        call_gate=lambda n, a: GateCallRecord(
            gate_name=n, arguments=a, result=a.get("answer")
        ),
    )
    assert out.done is True
    assert out.result == "ok"
    assert len(out.observation) == 1
    assert out.observation[0].gate_name == "done"


def test_subprocess_python_executor_ignores_regular_stdout_noise() -> None:
    ex = SubprocessPythonExecutor(timeout_s=2.0)
    out = ex.execute(
        "print('hello from code')\nresult = 7", call_gate=lambda _n, _a: None
    )
    assert out.done is False
    assert out.result == 7


def test_subprocess_python_executor_blocks_delegation_gate_calls() -> None:
    ex = SubprocessPythonExecutor(timeout_s=2.0)
    with pytest.raises(RuntimeError, match="delegation gate calls"):
        ex.execute("call_entity({'intent':'x'})", call_gate=lambda _n, _a: None)


<<<<<<< HEAD
def test_mini_code_executor_rejects_legacy_call_agent_alias() -> None:
    ex = MiniCodeExecutor()
    with pytest.raises(NameError, match="call_agent"):
        ex.execute("call_agent({intent:'x'})", call_gate=lambda _n, _a: None)
=======
def test_mini_code_executor_accepts_call_agent_alias() -> None:
    """call_agent is accepted as an alias for call_entity."""
    ex = MiniCodeExecutor()
    calls = []
    def call_gate(name, args):
        calls.append((name, args))
        return GateCallRecord(gate_name=name, arguments=args, result="ok")
    ex.execute("call_agent({intent:'x'})", call_gate=call_gate)
    assert calls and calls[0][0] == "call_entity"
>>>>>>> monorepo/main
