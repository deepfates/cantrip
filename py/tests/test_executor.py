from __future__ import annotations

import pytest

from cantrip.executor import MiniCodeExecutor, SubprocessPythonExecutor


def test_subprocess_python_executor_returns_result() -> None:
    ex = SubprocessPythonExecutor(timeout_s=2.0)
    out = ex.execute("result = 6 * 7", call_gate=lambda _n, _a: None)
    assert out.done is True
    assert out.result == 42


def test_subprocess_python_executor_blocks_gate_calls() -> None:
    ex = SubprocessPythonExecutor(timeout_s=2.0)
    with pytest.raises(RuntimeError, match="gate calls"):
        ex.execute("done(42)", call_gate=lambda _n, _a: None)


def test_mini_code_executor_rejects_legacy_call_agent_alias() -> None:
    ex = MiniCodeExecutor()
    with pytest.raises(NameError, match="call_agent"):
        ex.execute("call_agent({intent:'x'})", call_gate=lambda _n, _a: None)
