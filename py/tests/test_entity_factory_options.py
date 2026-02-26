from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal
from cantrip.browser import BrowserDriver


def test_call_entity_can_override_child_medium_to_browser() -> None:
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "code": (
                        "var r = call_entity({intent:'child', medium:'browser'});"
                        "done(r);"
                    )
                }
            ]
        }
    )
    child = FakeCrystal({"responses": [{"content": "navigated"}]})
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 4}, {"max_depth": 1}],
            medium="code",
        ),
    )
    assert cantrip.cast("parent") == "navigated"


def test_call_entity_can_override_child_code_runner_dependency() -> None:
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {
                            "gate": "call_entity",
                            "args": {
                                "intent": "child",
                                "medium": "code",
                                "depends": {"code": {"runner": "python-subprocess"}},
                            },
                        },
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                }
            ]
        }
    )
    child = FakeCrystal({"responses": [{"content": "result = 6 * 7"}]})
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(gates=["done", "call_entity"], wards=[{"max_turns": 4}]),
    )
    result, thread = cantrip.cast_with_thread("parent")
    assert result == "ok"
    call_entity_rec = thread.turns[0].observation[0]
    assert call_entity_rec.is_error is False
    assert call_entity_rec.result == 42


class _RecordingBrowserSession:
    def __init__(self, sink: list[str]) -> None:
        self.sink = sink

    def open(self, url: str):
        self.sink.append(f"open:{url}")
        return {"url": url}

    def click(self, selector: str):
        self.sink.append(f"click:{selector}")
        return {"clicked": selector}

    def type(self, selector: str, text: str):
        self.sink.append(f"type:{selector}:{text}")
        return {"typed": selector}

    def text(self, selector: str) -> str:
        self.sink.append(f"text:{selector}")
        return ""

    def url(self) -> str:
        self.sink.append("url")
        return ""

    def title(self) -> str:
        self.sink.append("title")
        return ""

    def close(self) -> None:
        self.sink.append("close")


class _NamedBrowserDriver(BrowserDriver):
    def __init__(self, name: str, sink: list[str]) -> None:
        self.name = name
        self.sink = sink

    def create_session(self):
        self.sink.append(f"session:{self.name}")
        return _RecordingBrowserSession(self.sink)


def test_call_entity_can_override_child_browser_driver_dependency() -> None:
    events: list[str] = []
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {
                            "gate": "call_entity",
                            "args": {
                                "intent": "child",
                                "medium": "browser",
                                "depends": {"browser": {"driver": "memory"}},
                            },
                        },
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                }
            ]
        }
    )
    child = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {
                            "gate": "browser",
                            "args": {"action": "open", "url": "https://example.com"},
                        },
                        {"gate": "done", "args": {"answer": "child-ok"}},
                    ]
                }
            ]
        }
    )
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        crystals={"child_crystal": child},
        circle=Circle(gates=["done", "call_entity"], wards=[{"max_turns": 4}]),
        medium_depends={
            "browser": {"session_factory": _NamedBrowserDriver("default", events)}
        },
    )
    result, thread = cantrip.cast_with_thread("parent")
    assert result == "ok"
    call_entity_rec = thread.turns[0].observation[0]
    assert call_entity_rec.is_error is False
    assert call_entity_rec.result == "child-ok"
    assert "session:default" in events


def test_call_entity_batch_supports_mixed_child_medium_options() -> None:
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "code": (
                        "var out = call_entity_batch(["
                        "{intent:'a'},"
                        "{intent:'b', medium:'code', depends:{code:{runner:'python-subprocess'}}},"
                        "{intent:'c', medium:'browser', depends:{browser:{driver:'memory'}}}"
                        "]);"
                        'done(out.join(","));'
                    )
                }
            ]
        }
    )
    child = FakeCrystal(
        {
            "responses": [
                {"tool_calls": [{"gate": "done", "args": {"answer": "tool"}}]},
                {"content": "result = 'code'"},
                {
                    "tool_calls": [
                        {
                            "gate": "browser",
                            "args": {"action": "open", "url": "https://example.com"},
                        },
                        {"gate": "done", "args": {"answer": "browser"}},
                    ]
                },
            ]
        }
    )
    events: list[str] = []
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(
            gates=["done", "call_entity", "call_entity_batch"],
            wards=[{"max_turns": 4}, {"max_depth": 1}],
            medium="code",
        ),
        medium_depends={
            "browser": {"session_factory": _NamedBrowserDriver("default", events)}
        },
    )
    assert cantrip.cast("parent") == "tool,code,browser"
    assert "session:default" in events


def test_call_entity_rejects_legacy_override_keys() -> None:
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {
                            "gate": "call_entity",
                            "args": {
                                "intent": "child",
                                "dependencies": {
                                    "code": {"runner": "python-subprocess"}
                                },
                            },
                        },
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                }
            ]
        }
    )
    child = FakeCrystal(
        {"responses": [{"tool_calls": [{"gate": "done", "args": {"answer": "child"}}]}]}
    )
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(gates=["done", "call_entity"], wards=[{"max_turns": 3}]),
    )
    result, thread = cantrip.cast_with_thread("parent")
    assert result == "ok"
    rec = thread.turns[0].observation[0]
    assert rec.is_error is True
    assert "unknown call_entity arg" in rec.content


def test_call_entity_child_uses_circle_depends_over_global_medium_depends() -> None:
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {
                            "gate": "call_entity",
                            "args": {"intent": "child", "medium": "code"},
                        },
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                }
            ]
        }
    )
    # This payload needs the python subprocess runner; mini runner cannot import.
    child = FakeCrystal(
        {"responses": [{"content": "import json\nresult = json.dumps({'ok': True})"}]}
    )
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 3}, {"max_depth": 1}],
            depends={"code": {"runner": "mini"}},
        ),
        medium_depends={"code": {"runner": "python-subprocess"}},
    )
    result, thread = cantrip.cast_with_thread("parent")
    assert result == "ok"
    rec = thread.turns[0].observation[0]
    assert rec.is_error is True
    assert "child failed" in rec.content


def test_call_entity_depends_override_beats_circle_depends_for_child_runtime() -> None:
    parent = FakeCrystal(
        {
            "responses": [
                {
                    "tool_calls": [
                        {
                            "gate": "call_entity",
                            "args": {
                                "intent": "child",
                                "medium": "code",
                                "depends": {"code": {"runner": "python-subprocess"}},
                            },
                        },
                        {"gate": "done", "args": {"answer": "ok"}},
                    ]
                }
            ]
        }
    )
    child = FakeCrystal(
        {"responses": [{"content": "import json\nresult = json.dumps({'ok': True})"}]}
    )
    cantrip = Cantrip(
        crystal=parent,
        child_crystal=child,
        circle=Circle(
            gates=["done", "call_entity"],
            wards=[{"max_turns": 3}, {"max_depth": 1}],
            depends={"code": {"runner": "mini"}},
        ),
        medium_depends={"code": {"runner": "mini"}},
    )
    result, thread = cantrip.cast_with_thread("parent")
    assert result == "ok"
    rec = thread.turns[0].observation[0]
    assert rec.is_error is False
    assert rec.result == '{"ok": true}'
