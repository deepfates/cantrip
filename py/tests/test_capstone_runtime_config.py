from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CAPSTONE_PATH = ROOT / "scripts" / "capstone.py"
SPEC = importlib.util.spec_from_file_location("capstone_script", CAPSTONE_PATH)
assert SPEC and SPEC.loader
capstone = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capstone)


def test_build_real_cantrip_uses_subprocess_runner_when_selected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("CANTRIP_OPENAI_MODEL", "gpt-test")
    monkeypatch.setenv("CANTRIP_OPENAI_BASE_URL", "http://localhost:11434/v1")
    monkeypatch.setenv("CANTRIP_CAPSTONE_CODE_TIMEOUT_S", "7")
    cantrip = capstone.build_real_cantrip(
        Path(".").resolve(), code_runner="python-subprocess"
    )
    assert cantrip.circle.depends["code"]["runner"] == "python-subprocess"
    assert cantrip.circle.depends["code"]["timeout_s"] == 7.0


def test_build_fake_cantrip_defaults_to_mini_runtime_depends() -> None:
    cantrip = capstone.build_fake_cantrip(Path(".").resolve())
    assert cantrip.circle.depends["code"]["runner"] == "mini"
    assert cantrip.circle.depends["browser"]["driver"] == "memory"
    assert cantrip.circle.medium == "tool"


def test_build_cantrip_invalid_code_runner_surfaces_error() -> None:
    with pytest.raises(SystemExit, match="Unknown code runner"):
        capstone.build_fake_cantrip(Path(".").resolve(), code_runner="invalid")


def test_build_fake_cantrip_supports_playwright_browser_driver() -> None:
    cantrip = capstone.build_fake_cantrip(
        Path(".").resolve(), browser_driver="playwright"
    )
    assert cantrip.circle.depends["browser"]["driver"] == "playwright"


def test_build_cantrip_invalid_browser_driver_surfaces_error() -> None:
    with pytest.raises(SystemExit, match="Unknown browser driver"):
        capstone.build_fake_cantrip(Path(".").resolve(), browser_driver="invalid")


def test_build_fake_cantrip_honors_medium_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CANTRIP_CAPSTONE_MEDIUM", "browser")
    cantrip = capstone.build_fake_cantrip(Path(".").resolve())
    assert cantrip.circle.medium == "browser"
