from __future__ import annotations

from pathlib import Path

from cantrip.cli import _resolve_repo_root


def test_repo_root_defaults_to_git_toplevel(tmp_path, monkeypatch) -> None:
    repo = tmp_path / "repo"
    nested = repo / "a" / "b"
    nested.mkdir(parents=True)
    (repo / ".git").mkdir()
    monkeypatch.chdir(nested)

    assert _resolve_repo_root(None) == repo.resolve()


def test_repo_root_defaults_to_cwd_when_no_git(tmp_path, monkeypatch) -> None:
    cwd = tmp_path / "no_repo"
    cwd.mkdir()
    monkeypatch.chdir(cwd)

    assert _resolve_repo_root(None) == cwd.resolve()


def test_repo_root_explicit_override_wins(tmp_path, monkeypatch) -> None:
    repo = tmp_path / "repo"
    nested = repo / "nested"
    override = tmp_path / "override"
    nested.mkdir(parents=True)
    override.mkdir()
    (repo / ".git").mkdir()
    monkeypatch.chdir(nested)

    assert _resolve_repo_root(str(override)) == override.resolve()
