from collections.abc import AsyncIterator

import pytest
from httpx2 import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool

from dinatos_backend.db import get_db
from dinatos_backend.main import app
from dinatos_backend.models.base import Base

TEST_USER_EMAIL = "test@example.com"
TEST_USER_PASSWORD = "hunter22"


@pytest.fixture
async def session_factory() -> AsyncIterator[async_sessionmaker[AsyncSession]]:
    # A file-less sqlite database, kept alive for the fixture's lifetime by
    # StaticPool (the default pool would otherwise open a fresh, empty
    # in-memory database on every checkout).
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        yield async_sessionmaker(engine, expire_on_commit=False)
    finally:
        await engine.dispose()


@pytest.fixture
async def db(
    session_factory: async_sessionmaker[AsyncSession],
) -> AsyncIterator[AsyncSession]:
    async with session_factory() as session:
        yield session


@pytest.fixture
async def anonymous_client(
    session_factory: async_sessionmaker[AsyncSession],
) -> AsyncIterator[AsyncClient]:
    """An unauthenticated client -- for the auth endpoints themselves, and
    for asserting that a protected endpoint actually rejects no token.
    """

    async def override_get_db() -> AsyncIterator[AsyncSession]:
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http_client:
        yield http_client
    app.dependency_overrides.clear()


@pytest.fixture
async def client(anonymous_client: AsyncClient) -> AsyncClient:
    """The default, authenticated client every non-auth test should use."""
    await anonymous_client.post(
        "/auth/register", json={"email": TEST_USER_EMAIL, "password": TEST_USER_PASSWORD}
    )
    login = await anonymous_client.post(
        "/auth/login", json={"email": TEST_USER_EMAIL, "password": TEST_USER_PASSWORD}
    )
    token = login.json()["access_token"]
    anonymous_client.headers["Authorization"] = f"Bearer {token}"
    return anonymous_client
