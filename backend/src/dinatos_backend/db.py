from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from dinatos_backend.config import get_settings

# Created eagerly, but `create_async_engine` doesn't open a connection until
# first use, so importing this module never requires a reachable database --
# tests override `get_db` below and never touch this engine at all.
engine = create_async_engine(get_settings().database_url)
async_session_factory = async_sessionmaker(engine, expire_on_commit=False)


async def get_db() -> AsyncIterator[AsyncSession]:
    async with async_session_factory() as session:
        yield session
