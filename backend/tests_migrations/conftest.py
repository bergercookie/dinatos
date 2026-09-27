"""Fixtures for exercising Alembic migrations against a real Postgres.

Deliberately not under `tests/`: these need Docker (via testcontainers) and
take real seconds to run, so they are not part of the always-available
`just test` -- see `just test-migrations` and AGENTS.md.
"""

import asyncio
from collections.abc import Iterator

import pytest
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine
from testcontainers.community.postgres import PostgresContainer

from dinatos_backend.config import get_settings


@pytest.fixture(scope="module")
def postgres_url() -> Iterator[str]:
    with PostgresContainer(
        "postgres:16-alpine", username="dinatos", password="dinatos", dbname="dinatos"
    ) as container:
        yield container.get_connection_url(driver="asyncpg")


@pytest.fixture
def alembic_engine(postgres_url: str, monkeypatch: pytest.MonkeyPatch) -> Iterator[AsyncEngine]:
    """The connectable pytest-alembic hands to its own tests.

    Migrations still run through our own `alembic/env.py`, exactly as the
    CLI would -- pytest-alembic doesn't bypass it -- and that reads the
    database URL through `Settings` (`get_settings()` is cached), so the
    container's URL has to land in `DINATOS_DATABASE_URL` too, not just be
    handed here as an engine.
    """
    monkeypatch.setenv("DINATOS_DATABASE_URL", postgres_url)
    get_settings.cache_clear()

    engine = create_async_engine(postgres_url)
    try:
        yield engine
    finally:
        asyncio.run(engine.dispose())
        get_settings.cache_clear()
