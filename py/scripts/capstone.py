#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from cantrip.builders import (
    build_cantrip_from_env,
    resolve_browser_driver,
    resolve_code_runner,
)
from cantrip.cli import main


def _legacy_validate_choices(
    *, code_runner: str | None = None, browser_driver: str | None = None
) -> None:
    try:
        if code_runner is not None:
            resolve_code_runner(code_runner)
        if browser_driver is not None:
            resolve_browser_driver(browser_driver)
    except ValueError as e:
        msg = str(e)
        if "code runner" in msg:
            raise SystemExit(f"Unknown code runner: {code_runner}") from e
        if "browser driver" in msg:
            raise SystemExit(f"Unknown browser driver: {browser_driver}") from e
        raise


def build_real_cantrip(
    repo_root: Path,
    *,
    code_runner: str | None = None,
    browser_driver: str | None = None,
):
    _legacy_validate_choices(code_runner=code_runner, browser_driver=browser_driver)
    return build_cantrip_from_env(
        repo_root=repo_root,
        dotenv=".env",
        fake=False,
        code_runner=code_runner,
        browser_driver=browser_driver,
    )


def build_fake_cantrip(
    repo_root: Path,
    *,
    code_runner: str | None = None,
    browser_driver: str | None = None,
):
    _legacy_validate_choices(code_runner=code_runner, browser_driver=browser_driver)
    return build_cantrip_from_env(
        repo_root=repo_root,
        dotenv=".env",
        fake=True,
        code_runner=code_runner,
        browser_driver=browser_driver,
    )


def build_cantrip(
    *,
    repo_root: Path,
    dotenv: str,
    fake: bool,
    code_runner: str | None = None,
    browser_driver: str | None = None,
):
    _legacy_validate_choices(code_runner=code_runner, browser_driver=browser_driver)
    return build_cantrip_from_env(
        repo_root=repo_root,
        dotenv=dotenv,
        fake=fake,
        code_runner=code_runner,
        browser_driver=browser_driver,
    )


if __name__ == "__main__":
    raise SystemExit(main())
