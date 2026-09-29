from collections.abc import AsyncIterator
from pathlib import Path

import pytest
from fastapi import FastAPI
from httpx2 import ASGITransport, AsyncClient

from dinatos_backend.main import _mount_web_ui


@pytest.fixture
async def web_client(tmp_path: Path) -> AsyncIterator[AsyncClient]:
    """A standalone app with `_mount_web_ui` pointed at a throwaway
    directory -- not the real `app` from `main.py`, since that one decides
    whether to mount anything at import time, from `Settings.web_dir`.
    """
    (tmp_path / "index.html").write_text("<html>dinatos web ui</html>")
    (tmp_path / "main.dart.js").write_text("console.log('hi');")

    app = FastAPI()
    _mount_web_ui(app, tmp_path)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def test_root_serves_index(web_client: AsyncClient) -> None:
    response = await web_client.get("/")

    assert response.status_code == 200
    assert "dinatos web ui" in response.text


async def test_real_asset_is_served_as_is(web_client: AsyncClient) -> None:
    response = await web_client.get("/main.dart.js")

    assert response.status_code == 200
    assert "console.log" in response.text


async def test_unknown_path_falls_back_to_index(web_client: AsyncClient) -> None:
    """A deep link straight at a client-side route (e.g. someone bookmarked
    or refreshed on it) has no matching file on disk -- it should still get
    the app shell, not a bare 404.
    """
    response = await web_client.get("/workouts/123")

    assert response.status_code == 200
    assert "dinatos web ui" in response.text


async def test_disallowed_method_is_not_swallowed_by_the_fallback(web_client: AsyncClient) -> None:
    """The fallback in `_WebApp.get_response` only catches a 404 -- a method
    StaticFiles itself rejects (anything but GET/HEAD) must still surface as
    its own error, not get silently turned into the index page.
    """
    response = await web_client.post("/")

    assert response.status_code == 405


async def test_mount_web_ui_is_a_noop_without_a_build(tmp_path: Path) -> None:
    """A missing `web_dir` (the common case outside the Docker image --
    `just backend run`, every other test in this suite) leaves the app with
    no catch-all route at all, so a typo'd API path still 404s instead of
    silently returning 200.
    """
    app = FastAPI()
    _mount_web_ui(app, tmp_path / "does-not-exist")

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/")

    assert response.status_code == 404


async def test_real_app_mounts_nothing_without_a_web_build(anonymous_client: AsyncClient) -> None:
    """`web_dir` (see `config.py`) doesn't exist in this test environment --
    same as `just backend run` outside Docker -- so the real app behaves
    exactly as it did before `_WebApp` existed: no catch-all route here to
    accidentally shadow a typo'd API path with a 200.
    """
    response = await anonymous_client.get("/this-path-does-not-exist")

    assert response.status_code == 404
