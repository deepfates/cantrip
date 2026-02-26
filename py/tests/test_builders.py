from __future__ import annotations

import os
from pathlib import Path

from cantrip.builders import build_cantrip_from_env


def test_builders_load_relative_dotenv_from_repo_root(tmp_path, monkeypatch) -> None:
    repo_root = tmp_path / "repo"
    repo_root.mkdir()
    subdir = repo_root / "nested"
    subdir.mkdir()
    (repo_root / ".env").write_text("CANTRIP_BUILDER_SENTINEL=from_repo_root\n")

    monkeypatch.delenv("CANTRIP_BUILDER_SENTINEL", raising=False)
    monkeypatch.chdir(subdir)

    build_cantrip_from_env(repo_root=repo_root, fake=True, dotenv=".env")
    assert os.environ.get("CANTRIP_BUILDER_SENTINEL") == "from_repo_root"


def test_builders_load_absolute_dotenv_path(tmp_path, monkeypatch) -> None:
    repo_root = tmp_path / "repo"
    repo_root.mkdir()
    dotenv_path = tmp_path / "custom.env"
    dotenv_path.write_text("CANTRIP_BUILDER_SENTINEL_ABS=from_abs_path\n")

    monkeypatch.delenv("CANTRIP_BUILDER_SENTINEL_ABS", raising=False)

    build_cantrip_from_env(repo_root=repo_root, fake=True, dotenv=str(dotenv_path))
    assert os.environ.get("CANTRIP_BUILDER_SENTINEL_ABS") == "from_abs_path"


def test_builders_support_disabling_provider_timeout(monkeypatch, tmp_path) -> None:
    repo_root = tmp_path / "repo"
    repo_root.mkdir()

    monkeypatch.setenv("CANTRIP_OPENAI_MODEL", "gpt-test")
    monkeypatch.setenv("CANTRIP_OPENAI_BASE_URL", "https://api.openai.com/v1")
    monkeypatch.setenv("CANTRIP_OPENAI_TIMEOUT_S", "0")

    cantrip = build_cantrip_from_env(repo_root=repo_root, fake=False, dotenv=".env")
    assert cantrip.crystal.timeout_s is None
