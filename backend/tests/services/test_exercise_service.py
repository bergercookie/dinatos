import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from dinatos_backend.config import Settings
from dinatos_backend.models.exercise import Equipment, Exercise, MuscleGroup
from dinatos_backend.services.exercise import bootstrap_default_exercises, exercise_muscles
from dinatos_backend.services.tutorials.free_exercise_db import load_free_exercise_db


def test_exercise_muscles_a_muscle_listed_as_both_counts_as_primary() -> None:
    """A handful of the vendored dataset's own entries list the same muscle
    in both `primaryMuscles` and `secondaryMuscles` (e.g. "Clean and
    Press"'s `shoulders`) -- `ExerciseMuscle`'s (exercise, muscle)
    uniqueness means both can't be stored, so primary wins.
    """
    rows = exercise_muscles(["shoulders"], ["shoulders", "triceps"])

    assert [(row.muscle, row.is_primary) for row in rows] == [
        (MuscleGroup.shoulders, True),
        (MuscleGroup.triceps, False),
    ]


async def test_bootstrap_default_exercises_seeds_an_empty_catalog(db: AsyncSession) -> None:
    await bootstrap_default_exercises(db)

    result = await db.execute(select(Exercise.name))
    names = set(result.scalars())
    assert names == {entry["name"] for entry in load_free_exercise_db()}


async def test_bootstrap_default_exercises_seeds_built_in_exercises(db: AsyncSession) -> None:
    """Seeded rows are the immutable, shipped catalog (see
    `Exercise.is_custom`'s docstring) -- never editable/deletable, unlike an
    exercise a person adds themselves.
    """
    await bootstrap_default_exercises(db)

    result = await db.execute(select(Exercise.is_custom))
    assert all(is_custom is False for is_custom in result.scalars())


async def test_bootstrap_default_exercises_infers_tracking_flags_by_category(
    db: AsyncSession,
) -> None:
    """A spot check of `_infer_tracking`'s category/force-based guess for
    a few concrete cases, rather than every one of ~876 entries.
    """
    await bootstrap_default_exercises(db)

    async def tracking(name: str) -> tuple[bool, bool, bool, bool]:
        result = await db.execute(select(Exercise).where(Exercise.name == name))
        exercise = result.scalar_one()
        return (
            exercise.tracks_weight,
            exercise.tracks_reps,
            exercise.tracks_distance,
            exercise.tracks_duration,
        )

    # strength, compound -> weight + reps
    assert await tracking("Barbell Deadlift") == (True, True, False, False)
    # cardio -> distance + duration, no weight/reps
    assert await tracking("Bicycling, Stationary") == (False, False, True, True)
    # stretching -> duration only
    assert await tracking("Ankle Circles") == (False, False, False, True)


async def test_bootstrap_default_exercises_seeds_equipment_and_muscle_groups(
    db: AsyncSession,
) -> None:
    """A spot check of one concrete entry, rather than every one of ~876 --
    see `services.exercise._equipment`/`_muscles` for how the dataset's own
    strings map onto these enums.
    """
    await bootstrap_default_exercises(db)

    result = await db.execute(
        select(Exercise)
        .where(Exercise.name == "Barbell Deadlift")
        .options(selectinload(Exercise.muscles))
    )
    exercise = result.scalar_one()
    assert exercise.equipment == Equipment.barbell
    assert exercise.primary_muscles == [MuscleGroup.lower_back]
    assert set(exercise.secondary_muscles) == {
        MuscleGroup.calves,
        MuscleGroup.forearms,
        MuscleGroup.glutes,
        MuscleGroup.hamstrings,
        MuscleGroup.lats,
        MuscleGroup.middle_back,
        MuscleGroup.quadriceps,
        MuscleGroup.traps,
    }


async def test_bootstrap_default_exercises_is_a_noop_with_any_existing_exercise(
    db: AsyncSession,
) -> None:
    """Table-wide, not per-name: once someone's deleted a seeded exercise
    they didn't want, it should stay gone, not reappear on the next
    restart.
    """
    db.add(Exercise(name="A Custom Exercise"))
    await db.commit()

    await bootstrap_default_exercises(db)

    result = await db.execute(select(Exercise.name))
    assert list(result.scalars()) == ["A Custom Exercise"]


async def test_bootstrap_default_exercises_is_a_noop_when_disabled_by_setting(
    db: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    """What `screenshots/generate.py` relies on to keep its own curated,
    demo-sized exercise list exactly what it creates.
    """
    monkeypatch.setattr(
        "dinatos_backend.services.exercise.get_settings",
        lambda: Settings(seed_default_exercises=False),
    )

    await bootstrap_default_exercises(db)

    result = await db.execute(select(Exercise.name))
    assert result.scalars().first() is None
