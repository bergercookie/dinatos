import importlib.util
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Session, selectinload

from dinatos_backend.models.exercise import Equipment, Exercise, ExerciseMuscle, MuscleGroup
from dinatos_backend.services.exercise import bootstrap_default_exercises
from dinatos_backend.services.exercise_additions import ADDITIONS
from dinatos_backend.services.tutorials.free_exercise_db import load_free_exercise_db

_MIGRATION = next(
    (Path(__file__).parents[2] / "alembic" / "versions").glob("*_add_rehab_exercises.py")
)


def _add_exercises(sync_session: Session) -> None:
    spec = importlib.util.spec_from_file_location("rehab_migration", _MIGRATION)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.add_exercises(sync_session.connection())


def test_additions_are_unique_and_do_not_clash_with_the_dataset() -> None:
    names = [a.name for a in ADDITIONS]
    assert len(names) == len(set(names))
    assert not set(names) & {e["name"] for e in load_free_exercise_db()}
    assert all(a.primary and any(a.specs) for a in ADDITIONS)


async def test_bootstrap_seeds_the_additions_too(db: AsyncSession) -> None:
    await bootstrap_default_exercises(db)

    names = set((await db.execute(select(Exercise.name))).scalars())
    assert {a.name for a in ADDITIONS} <= names


async def test_migration_leaves_an_empty_catalog_to_the_seeding(db: AsyncSession) -> None:
    await db.run_sync(_add_exercises)

    assert (await db.execute(select(Exercise))).first() is None


async def test_migration_adds_missing_and_adopts_identical_custom_exercise(
    db: AsyncSession,
) -> None:
    wall_sit = next(a for a in ADDITIONS if a.name == "Wall Sit")
    mine = Exercise(
        name="Wall Sit",
        tracks_weight=wall_sit.tracks_weight,
        tracks_reps=wall_sit.tracks_reps,
        tracks_distance=wall_sit.tracks_distance,
        tracks_duration=wall_sit.tracks_duration,
        is_custom=True,
    )
    different = Exercise(name="Nordic Hamstring Curl", tracks_weight=True, is_custom=True)
    db.add_all([mine, different, Exercise(name="Unrelated", is_custom=True)])
    await db.commit()
    mine_id, different_id = mine.id, different.id

    await db.run_sync(_add_exercises)
    await db.commit()
    db.expire_all()

    rows = {
        e.name: e
        for e in (
            await db.execute(select(Exercise).options(selectinload(Exercise.muscles)))
        ).scalars()
    }
    # The person's own row was adopted: same id (so logged data stays attached).
    assert rows["Wall Sit"].id == mine_id
    assert rows["Wall Sit"].is_custom is False
    assert rows["Wall Sit"].equipment == Equipment.body_only
    assert rows["Wall Sit"].primary_muscles == [MuscleGroup.quadriceps]
    # Same name, different tracking: left untouched.
    assert rows["Nordic Hamstring Curl"].id == different_id
    assert rows["Nordic Hamstring Curl"].is_custom is True
    assert rows["Nordic Hamstring Curl"].muscles == []
    # Everything else was created as a built-in; the unrelated one is unchanged.
    assert rows["Unrelated"].is_custom is True
    assert len(rows) == len(ADDITIONS) + 1
    assert all(not rows[a.name].is_custom for a in ADDITIONS if a.name != "Nordic Hamstring Curl")

    count = len((await db.execute(select(ExerciseMuscle))).scalars().all())
    assert count > 0

    # Running again changes nothing.
    await db.run_sync(_add_exercises)
    await db.commit()
    assert len((await db.execute(select(Exercise))).scalars().all()) == len(ADDITIONS) + 1
