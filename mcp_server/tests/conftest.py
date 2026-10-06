import asyncio
from collections.abc import AsyncIterator

import httpx
import pytest
from httpx import ASGITransport
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool

from dinatos_backend.api.mcp import mcp_gateway
from dinatos_backend.db import get_db
from dinatos_backend.main import app
from dinatos_backend.models.base import Base
from dinatos_mcp.config import get_settings
from dinatos_mcp.server import RemoteTools

TEST_USER_EMAIL = "test@example.com"
TEST_USER_PASSWORD = "hunter22"


@pytest.fixture(autouse=True)
def _fresh_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in ("DINATOS_MCP_BASE_URL", "DINATOS_MCP_API_KEY"):
        monkeypatch.delenv(name, raising=False)
    get_settings.cache_clear()


@pytest.fixture
async def backend_transport() -> AsyncIterator[ASGITransport]:
    """A real Dinatos backend app, in-process over an in-memory sqlite
    database -- no network, no separately running server -- with its MCP
    endpoint running. This package is a client of that endpoint, so its tests
    talk to the real thing rather than to hand-rolled fixtures.
    """
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async def override_get_db() -> AsyncIterator[AsyncSession]:
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db

    # The MCP transport's task group must be entered and left by one task.
    started, stop = asyncio.Event(), asyncio.Event()

    async def run_gateway() -> None:
        async with mcp_gateway.running():
            started.set()
            await stop.wait()

    gateway_task = asyncio.create_task(run_gateway())
    await started.wait()
    try:
        yield ASGITransport(app=app)
    finally:
        stop.set()
        await gateway_task
        app.dependency_overrides.clear()
        await engine.dispose()


@pytest.fixture
async def api_key(backend_transport: ASGITransport) -> str:
    async with httpx.AsyncClient(transport=backend_transport, base_url="http://test") as http:
        await http.post(
            "/auth/register", json={"email": TEST_USER_EMAIL, "password": TEST_USER_PASSWORD}
        )
        login = await http.post(
            "/auth/login", json={"email": TEST_USER_EMAIL, "password": TEST_USER_PASSWORD}
        )
        http.headers["Authorization"] = f"Bearer {login.json()['access_token']}"
        created = await http.post("/api-keys", json={"name": "test"})
        key: str = created.json()["key"]
        return key


@pytest.fixture
def configured(monkeypatch: pytest.MonkeyPatch, api_key: str) -> str:
    monkeypatch.setenv("DINATOS_MCP_BASE_URL", "http://test")
    monkeypatch.setenv("DINATOS_MCP_API_KEY", api_key)
    get_settings.cache_clear()
    return api_key


@pytest.fixture
def remote(backend_transport: ASGITransport) -> RemoteTools:
    """The proxy's client side, routed to the in-process backend."""

    def factory(
        headers: dict[str, str] | None = None,
        timeout: httpx.Timeout | None = None,
        auth: httpx.Auth | None = None,
    ) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            transport=backend_transport,
            base_url="http://test",
            headers=headers,
            timeout=timeout,
            auth=auth,
            follow_redirects=True,
        )

    return RemoteTools(http_client_factory=factory)
