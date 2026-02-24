from __future__ import annotations

from pathlib import Path

from cantrip import Cantrip, Circle, FakeCrystal


def test_repo_files_lists_files_under_root(tmp_path: Path) -> None:
    (tmp_path / "a.txt").write_text("a")
    (tmp_path / "dir").mkdir()
    (tmp_path / "dir" / "b.py").write_text("print('x')\n")

    crystal = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {"gate": "repo_files", "args": {"glob": "**/*", "limit": 10}},
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                }
            ]
        }
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(
            gates=[
                "done",
                {"name": "repo_files", "depends": {"root": str(tmp_path)}},
            ],
            wards=[{"max_turns": 3}],
        ),
    )
    result, thread = cantrip.cast_with_thread("list files")
    assert result == "ok"
    files = thread.turns[0].observation[0].result
    assert files == ["a.txt", "dir/b.py"]


def test_repo_read_reads_file(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("hello repo\n")
    crystal = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {"gate": "repo_read", "args": {"path": "README.md"}},
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                }
            ]
        }
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(
            gates=[
                "done",
                {"name": "repo_read", "depends": {"root": str(tmp_path)}},
            ],
            wards=[{"max_turns": 3}],
        ),
    )
    _result, thread = cantrip.cast_with_thread("read file")
    assert thread.turns[0].observation[0].result == "hello repo\n"


def test_repo_read_blocks_path_escape(tmp_path: Path) -> None:
    crystal = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {"gate": "repo_read", "args": {"path": "../secrets.txt"}},
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                }
            ]
        }
    )
    cantrip = Cantrip(
        crystal=crystal,
        circle=Circle(
            gates=[
                "done",
                {"name": "repo_read", "depends": {"root": str(tmp_path)}},
            ],
            wards=[{"max_turns": 3}],
        ),
    )
    _result, thread = cantrip.cast_with_thread("escape")
    err = thread.turns[0].observation[0]
    assert err.is_error is True
    assert "path escapes root" in err.content
