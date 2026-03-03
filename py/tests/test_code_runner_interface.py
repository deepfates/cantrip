from __future__ import annotations

from cantrip import Cantrip, Circle, FakeLLM
from cantrip.executor import CodeExecResult


class _StaticDoneExecutor:
    def execute(self, source, call_gate):
        rec = call_gate("done", {"answer": "from-runner"})
        return CodeExecResult(observation=[rec], result="from-runner", done=True)


def test_cantrip_uses_injected_executor_for_code_medium() -> None:
    cantrip = Cantrip(
        llm=FakeLLM({"responses": [{"content": "ignored"}]}),
        circle=Circle(gates=["done"], wards=[{"max_turns": 2}], medium="code"),
        medium_depends={"code": {"executor": _StaticDoneExecutor()}},
    )
    assert cantrip.cast("run") == "from-runner"
