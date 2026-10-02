import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.exercise import Exercise
from dinatos_backend.models.user import User
from dinatos_backend.services.exercise import _default_exercises
from dinatos_backend.services.hevy_exercise_match import _ALIASES, CatalogMatcher
from dinatos_backend.services.hevy_import import import_hevy_workouts


def _catalog() -> list[Exercise]:
    return [Exercise(**fields) for fields in _default_exercises()]


def test_every_alias_targets_a_real_catalog_exercise() -> None:
    names = {e.name for e in _catalog()}
    assert [t for t in _ALIASES.values() if t not in names] == []


@pytest.mark.parametrize(
    ("hevy", "expected"),
    [
        ("Bench Press (Barbell)", "Barbell Bench Press - Medium Grip"),  # alias
        ("Squat (Barbell)", "Barbell Squat"),  # word order + equipment
        ("Bicep Curl (Dumbbell)", "Dumbbell Bicep Curl"),
        ("Deadlift (Barbell)", "Barbell Deadlift"),
        ("Lunge (Dumbbell)", "Dumbbell Lunges"),  # plural fold
        ("Plank", "Plank"),
        ("pull up", "Pullups"),
        # Titles taken from a real Hevy export.
        ("Squat (Smith Machine)", "Smith Machine Squat"),
        ("Front Raise (Dumbbell)", "Front Dumbbell Raise"),
        ("Triceps Kickback (Dumbbell)", "Tricep Dumbbell Kickback"),
        ("Hip Abduction (Machine)", "Thigh Abductor"),
        ("Farmers Walk", "Farmer's Walk"),
        ("Spinning", "Bicycling, Stationary"),
    ],
)
def test_matches_hevy_builtins(hevy: str, expected: str) -> None:
    match = CatalogMatcher(_catalog()).match(hevy)
    assert match is not None
    assert match.name == expected


@pytest.mark.parametrize(
    "hevy", ["My Weird Custom Movement", "Squat (Banana)", "Squat (Band)", "Hip stretches", ""]
)
def test_unmatched_names_return_none(hevy: str) -> None:
    assert CatalogMatcher(_catalog()).match(hevy) is None


async def test_import_reuses_seeded_exercises(db: AsyncSession) -> None:
    db.add(User(email="m@example.com", password_hash="x"))
    db.add_all(_catalog())
    await db.commit()
    owner_id = (await db.execute(select(User.id))).scalar_one()
    before = len((await db.execute(select(Exercise))).scalars().all())

    csv_text = (
        "title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,"
        "set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe\n"
        'Push,"1 Jan 2026, 08:00","1 Jan 2026, 09:00",,Bench Press (Barbell),,,0,normal,60,5,,,\n'
        'Push,"1 Jan 2026, 08:00","1 Jan 2026, 09:00",,Homemade Thing,,,0,normal,10,5,,,\n'
    )
    result = await import_hevy_workouts(db, owner_id, csv_text)

    assert result.exercises_created == 1
    after = len((await db.execute(select(Exercise))).scalars().all())
    assert after == before + 1
