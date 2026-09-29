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

from dinatos_backend.db import get_db
from dinatos_backend.main import app
from dinatos_backend.models.base import Base
from dinatos_mcp.client import DinatosClient

TEST_USER_EMAIL = "test@example.com"
TEST_USER_PASSWORD = "hunter22"


@pytest.fixture
async def backend_transport() -> AsyncIterator[ASGITransport]:
    """A real Dinatos backend app, in-process over an in-memory sqlite
    database -- no network, no separately running server. Mirrors
    backend/tests/conftest.py's own fixtures, one level up: this package
    is a client of that API, not a part of it, so its tests exercise the
    real request/response shapes rather than hand-rolled fixtures.
    """
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async def override_get_db() -> AsyncIterator[AsyncSession]:
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    try:
        yield ASGITransport(app=app)
    finally:
        app.dependency_overrides.clear()
        await engine.dispose()


@pytest.fixture
async def anonymous_http(backend_transport: ASGITransport) -> AsyncIterator[httpx.AsyncClient]:
    async with httpx.AsyncClient(transport=backend_transport, base_url="http://test") as http:
        yield http


@pytest.fixture
async def registered_user(anonymous_http: httpx.AsyncClient) -> None:
    response = await anonymous_http.post(
        "/auth/register", json={"email": TEST_USER_EMAIL, "password": TEST_USER_PASSWORD}
    )
    assert response.status_code == 201


@pytest.fixture
async def client(
    backend_transport: ASGITransport,
    registered_user: None,  # noqa: ARG001 -- depended on for its side effect, not its value
) -> AsyncIterator[DinatosClient]:
    """The default, already-authenticated client every test should use
    unless it's specifically exercising the login-on-first-use path.
    """
    async with httpx.AsyncClient(transport=backend_transport, base_url="http://test") as http:
        login = await http.post(
            "/auth/login", json={"email": TEST_USER_EMAIL, "password": TEST_USER_PASSWORD}
        )
        http.headers["Authorization"] = f"Bearer {login.json()['access_token']}"
        yield DinatosClient(http)
