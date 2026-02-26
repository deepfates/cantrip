from __future__ import annotations

from cantrip import Cantrip, Circle, FakeCrystal


class _FakeBrowserSession:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []
        self.closed = 0

    def open(self, url: str):
        self.calls.append(("open", url))
        return {"url": url}

    def close(self) -> None:
        self.closed += 1


class _FakeBrowserDriver:
    def __init__(self) -> None:
        self.session = _FakeBrowserSession()

    def create_session(self):
        return self.session


def test_browser_medium_processes_browser_tool_calls() -> None:
    driver = _FakeBrowserDriver()
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {
                        "tool_calls": [
                            {
                                "gate": "browser",
                                "args": {
                                    "action": "open",
                                    "url": "https://example.com",
                                },
                            },
                            {"gate": "done", "args": {"answer": "ok"}},
                        ]
                    }
                ]
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}], medium="browser"),
        medium_depends={"browser": {"session_factory": driver}},
    )
    result, thread = cantrip.cast_with_thread("browse")
    assert result == "ok"
    assert driver.session.calls == [("open", "https://example.com")]
    assert thread.turns[0].observation[0].is_error is False
    assert thread.turns[0].observation[0].gate_name == "browser"
    assert thread.turns[0].observation[0].result["url"] == "https://example.com"
    assert driver.session.closed == 1


def test_browser_medium_closes_runtime_when_browser_action_errors() -> None:
    driver = _FakeBrowserDriver()
    cantrip = Cantrip(
        crystal=FakeCrystal(
            {
                "responses": [
                    {
                        "tool_calls": [
                            {"gate": "browser", "args": {"action": "open"}},
                            {"gate": "done", "args": {"answer": "ok"}},
                        ]
                    }
                ]
            }
        ),
        circle=Circle(gates=["done"], wards=[{"max_turns": 3}], medium="browser"),
        medium_depends={"browser": {"session_factory": driver}},
    )
    result, thread = cantrip.cast_with_thread("browse")
    assert result == "ok"
    assert thread.turns[0].observation[0].is_error is True
    assert "url is required" in thread.turns[0].observation[0].content
    assert driver.session.closed == 1
