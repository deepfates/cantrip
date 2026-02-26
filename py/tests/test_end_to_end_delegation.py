from __future__ import annotations

from cantrip import Call, Cantrip, Circle, FakeCrystal


def test_end_to_end_delegated_repo_workflow(tmp_path) -> None:
    repo_root = tmp_path
    sample = repo_root / "sample.txt"
    sample.write_text("delegation-e2e-ok", encoding="utf-8")

    parent = FakeCrystal(
        {
            "responses": [
                {
                    "code": (
                        "var r = call_entity({"
                        "intent: 'child-inspect',"
                        "medium: 'tool',"
                        "gates: ['done','repo_files','repo_read'],"
                        "crystal: 'child'"
                        "});"
                        "done(r);"
                    )
                }
            ]
        }
    )
    child = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {"gate": "repo_files", "args": {"glob": "*.txt", "limit": 10}},
                        {"gate": "repo_read", "args": {"path": "sample.txt"}},
                        {"gate": "done", "args": {"answer": "child-ok"}},
                    ]
                }
            ]
        }
    )

    cantrip = Cantrip(
        crystal=parent,
        crystals={"child": child},
        circle=Circle(
            medium="code",
            gates=[
                "done",
                "call_entity",
                {"name": "repo_files", "depends": {"root": str(repo_root)}},
                {"name": "repo_read", "depends": {"root": str(repo_root)}},
            ],
            wards=[{"max_turns": 4}, {"max_depth": 2}],
            depends={"code": {"runner": "mini"}},
        ),
        call=Call(require_done_tool=True, tool_choice="required"),
    )

    result, parent_thread = cantrip.cast_with_thread("delegate now")

    assert result == "child-ok"
    assert parent_thread.terminated is True
    assert parent_thread.turns
    assert any(
        rec.gate_name == "call_entity" and rec.result == "child-ok"
        for rec in parent_thread.turns[0].observation
    )

    threads = cantrip.loom.list_threads()
    child_threads = [t for t in threads if t.id != parent_thread.id]
    assert child_threads
    child_thread = child_threads[0]
    repo_read_recs = [
        rec
        for turn in child_thread.turns
        for rec in turn.observation
        if rec.gate_name == "repo_read" and not rec.is_error
    ]
    assert repo_read_recs
    assert "delegation-e2e-ok" in str(repo_read_recs[0].result)
