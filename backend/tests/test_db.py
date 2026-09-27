import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from dinatos_backend import db


async def test_get_db_yields_a_working_session(
    monkeypatch: pytest.MonkeyPatch, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    monkeypatch.setattr(db, "async_session_factory", session_factory)

    agen = db.get_db()
    session = await anext(agen)
    assert isinstance(session, AsyncSession)

    with pytest.raises(StopAsyncIteration):
        await anext(agen)
