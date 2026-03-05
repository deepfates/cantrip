from __future__ import annotations

from contextlib import redirect_stderr
from io import StringIO

from cantrip import acp_stdio


def test_main_requires_host_wiring_and_returns_nonzero() -> None:
    err = StringIO()
    with redirect_stderr(err):
        code = acp_stdio.main()
    assert code == 2
    assert "requires explicit cantrip wiring" in err.getvalue()
