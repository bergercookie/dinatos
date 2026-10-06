from importlib.metadata import version

import pytest

import dinatos_backend
from dinatos_backend.main import app


def test_version_is_the_installed_packages_not_a_constant() -> None:
    # A release build stamps its version into pyproject.toml (see the
    # Dockerfile); the API must report whatever the package says.
    assert dinatos_backend.__version__ == version("dinatos-backend")
    assert app.version == dinatos_backend.__version__


def test_version_falls_back_when_the_package_is_not_installed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import importlib
    from importlib import metadata

    def missing(name: str) -> str:
        raise metadata.PackageNotFoundError(name)

    monkeypatch.setattr(metadata, "version", missing)
    try:
        assert importlib.reload(dinatos_backend).__version__ == "0.1.0"
    finally:
        monkeypatch.undo()
        importlib.reload(dinatos_backend)
