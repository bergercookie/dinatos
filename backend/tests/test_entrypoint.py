from typing import Any

import pytest
import uvicorn

from dinatos_backend.__main__ import main


def test_serves_on_the_default_address(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DINATOS_HOST", raising=False)
    monkeypatch.delenv("DINATOS_PORT", raising=False)

    served: dict[str, Any] = {}
    monkeypatch.setattr(uvicorn, "run", lambda _app, **kwargs: served.update(kwargs))

    main()

    assert served["host"] == "127.0.0.1"
    assert served["port"] == 8000


def test_serves_on_the_configured_address(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DINATOS_HOST", "0.0.0.0")
    monkeypatch.setenv("DINATOS_PORT", "9000")

    served: dict[str, Any] = {}
    monkeypatch.setattr(uvicorn, "run", lambda _app, **kwargs: served.update(kwargs))

    main()

    assert served["host"] == "0.0.0.0"
    assert served["port"] == 9000
