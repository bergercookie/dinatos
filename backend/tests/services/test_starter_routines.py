import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.config import Settings
from dinatos_backend.models.routine import Routine
from dinatos_backend.services.auth import create_user
from dinatos_backend.services.exercise import bootstrap_default_exercises


async def _routines(db: AsyncSession, owner_id: int) -> list[Routine]:
    result = await db.execute(select(Routine).where(Routine.owner_id == owner_id))
    return list(result.scalars())


async def test_new_account_gets_starter_routines(db: AsyncSession) -> None:
    await bootstrap_default_exercises(db)

    user = await create_user(db, "a@example.com", "hunter22")

    routines = await _routines(db, user.id)
    assert [r.name for r in routines] == [
        "Push",
        "Pull",
        "Legs",
        "Upper body",
        "Lower body",
        "Full body",
    ]
    for routine in routines:
        await db.refresh(routine, ["exercises"])
        assert routine.exercises
        for item in routine.exercises:
            await db.refresh(item, ["sets"])
            assert item.sets


async def test_each_account_gets_its_own_copy(db: AsyncSession) -> None:
    await bootstrap_default_exercises(db)

    first = await create_user(db, "a@example.com", "hunter22")
    second = await create_user(db, "b@example.com", "hunter22")

    first_ids = {r.id for r in await _routines(db, first.id)}
    second_ids = {r.id for r in await _routines(db, second.id)}
    assert first_ids and second_ids and not first_ids & second_ids


async def test_no_routines_without_the_exercise_catalog(db: AsyncSession) -> None:
    user = await create_user(db, "a@example.com", "hunter22")

    assert await _routines(db, user.id) == []


async def test_disabled_by_setting(db: AsyncSession, monkeypatch: pytest.MonkeyPatch) -> None:
    await bootstrap_default_exercises(db)
    monkeypatch.setattr(
        "dinatos_backend.services.starter_routines.get_settings",
        lambda: Settings(seed_default_routines=False),
    )

    user = await create_user(db, "a@example.com", "hunter22")

    assert await _routines(db, user.id) == []
