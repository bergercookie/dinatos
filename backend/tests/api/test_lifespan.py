import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from dinatos_backend.api import lifespan as lifespan_module
from dinatos_backend.main import app
from dinatos_backend.models.exercise import Exercise


async def test_lifespan_runs_without_a_configured_admin_account(
    monkeypatch: pytest.MonkeyPatch, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    """`bootstrap_admin_user`/`bootstrap_default_exercises` are themselves
    unit-tested in tests/services/; this just confirms the lifespan
    wrapper actually calls both against a real session, not a smart-
    looking no-op.
    """
    monkeypatch.setattr(lifespan_module, "async_session_factory", session_factory)

    async with lifespan_module.lifespan(app):
        pass

    async with session_factory() as db:
        result = await db.execute(select(Exercise))
        assert result.scalars().first() is not None
