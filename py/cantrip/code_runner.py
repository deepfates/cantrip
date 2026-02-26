from __future__ import annotations

from abc import ABC, abstractmethod

from cantrip.errors import CantripError
from cantrip.executor import CodeExecutor, MiniCodeExecutor, SubprocessPythonExecutor


class CodeRunnerFactory(ABC):
    @abstractmethod
    def create_executor(self) -> CodeExecutor:
        raise NotImplementedError


class ExecutorClassRunnerFactory(CodeRunnerFactory):
    def __init__(self, executor_cls: type[CodeExecutor]) -> None:
        self.executor_cls = executor_cls

    def create_executor(self) -> CodeExecutor:
        return self.executor_cls()


class ExecutorInstanceRunnerFactory(CodeRunnerFactory):
    def __init__(self, executor: CodeExecutor) -> None:
        self.executor = executor

    def create_executor(self) -> CodeExecutor:
        return type(self.executor)()


class MiniCodeRunnerFactory(CodeRunnerFactory):
    def create_executor(self) -> CodeExecutor:
        return MiniCodeExecutor()


class SubprocessPythonRunnerFactory(CodeRunnerFactory):
    def __init__(self, timeout_s: float = 5.0) -> None:
        self.timeout_s = timeout_s

    def create_executor(self) -> CodeExecutor:
        return SubprocessPythonExecutor(timeout_s=self.timeout_s)


def code_runner_from_name(name: str | None) -> CodeRunnerFactory:
    key = (name or "mini").strip().lower()
    if key in {"mini", "mini-js", "minicode"}:
        return MiniCodeRunnerFactory()
    if key in {"python", "python-subprocess", "subprocess-python"}:
        return SubprocessPythonRunnerFactory()
    raise CantripError(f"unknown code runner: {name}")
