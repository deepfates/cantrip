from __future__ import annotations


def test_acp_stdio_exports_available_from_package_root() -> None:
    from cantrip import ACPStdioRouter, serve_stdio, serve_stdio_once  # noqa: PLC0415

    assert ACPStdioRouter is not None
    assert callable(serve_stdio)
    assert callable(serve_stdio_once)


def test_browser_and_sandbox_exports_available_from_package_root() -> None:
    import cantrip  # noqa: PLC0415

    assert not hasattr(cantrip, "BrowserBackend")
    assert not hasattr(cantrip, "InMemoryBrowserBackend")
    assert not hasattr(cantrip, "PlaywrightBrowserBackend")
    assert not hasattr(cantrip, "SandboxBackend")
    assert not hasattr(cantrip, "code_runner_from_name")
