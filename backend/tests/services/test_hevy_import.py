from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.activity import Activity
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.models.hevy_import import HevyImportKind
from dinatos_backend.models.measurement import BodyMeasurement
from dinatos_backend.models.user import User
from dinatos_backend.services.hevy_import import (
    find_previous_import,
    hash_csv_content,
    import_hevy_measurements,
    import_hevy_workouts,
    record_import,
)

FIXTURES = Path(__file__).parent.parent / "fixtures"


async def _create_user(db: AsyncSession, email: str = "owner@example.com") -> User:
    user = User(email=email, password_hash="not-a-real-hash")
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


async def test_import_workouts_groups_rows_into_activities(db: AsyncSession) -> None:
    owner = await _create_user(db)
    csv_text = (FIXTURES / "hevy_workouts_sample.csv").read_text()

    result = await import_hevy_workouts(db, owner.id, csv_text)

    assert result.activities_created == 3
    # Squat (Barbell), Plank, Elliptical Trainer, Bench Press (Dumbbell), Bicep Curl (Dumbbell)
    assert result.exercises_created == 5

    activities = (await db.execute(select(Activity).order_by(Activity.started_at))).scalars().all()
    assert [a.title for a in activities] == ["Leg Day", "Cardio", "Superset Day"]
    assert all(a.owner_id == owner.id for a in activities)

    leg_day = activities[0]
    # Squat appears as two separate instances (the set_index reset back to 0
    # for the back-off set), plus Plank -- three instances, not two.
    assert len(leg_day.exercises) == 3
    assert len(leg_day.exercises[0].sets) == 3
    assert leg_day.exercises[0].sets[0].set_type.value == "warmup"
    assert leg_day.exercises[2].notes == "back-off set"

    cardio = activities[1]
    assert cardio.description == "Easy morning session"
    assert cardio.exercises[0].sets[0].distance_km == 5.2
    assert cardio.exercises[0].sets[0].duration_seconds == 1800

    superset_day = activities[2]
    assert superset_day.exercises[0].superset_group == 0
    assert superset_day.exercises[1].superset_group == 0


async def test_import_workouts_infers_exercise_metric_flags(db: AsyncSession) -> None:
    owner = await _create_user(db)
    csv_text = (FIXTURES / "hevy_workouts_sample.csv").read_text()

    await import_hevy_workouts(db, owner.id, csv_text)

    squat = (
        (await db.execute(select(Exercise).where(Exercise.name == "Squat (Barbell)")))
        .scalars()
        .one()
    )
    assert squat.tracks_weight is True
    assert squat.tracks_reps is True
    assert squat.tracks_distance is False
    assert squat.tracks_duration is False

    plank = (await db.execute(select(Exercise).where(Exercise.name == "Plank"))).scalars().one()
    assert plank.tracks_weight is False
    assert plank.tracks_duration is True

    elliptical = (
        (await db.execute(select(Exercise).where(Exercise.name == "Elliptical Trainer")))
        .scalars()
        .one()
    )
    assert elliptical.tracks_distance is True
    assert elliptical.tracks_duration is True


async def test_import_workouts_reuses_existing_exercises(db: AsyncSession) -> None:
    owner = await _create_user(db)
    db.add(Exercise(name="Squat (Barbell)", tracks_weight=True, tracks_reps=True))
    await db.commit()

    csv_text = (FIXTURES / "hevy_workouts_sample.csv").read_text()
    result = await import_hevy_workouts(db, owner.id, csv_text)

    # Squat already existed, so only the other four are newly created.
    assert result.exercises_created == 4
    squats = (
        (await db.execute(select(Exercise).where(Exercise.name == "Squat (Barbell)")))
        .scalars()
        .all()
    )
    assert len(squats) == 1


async def test_import_measurements(db: AsyncSession) -> None:
    owner = await _create_user(db)
    csv_text = (FIXTURES / "hevy_measurements_sample.csv").read_text()

    result = await import_hevy_measurements(db, owner.id, csv_text)

    assert result.measurements_created == 2
    measurements = (
        (await db.execute(select(BodyMeasurement).order_by(BodyMeasurement.measured_at)))
        .scalars()
        .all()
    )
    assert measurements[0].weight_kg == 80.0
    assert measurements[0].fat_percent is None
    assert measurements[0].owner_id == owner.id
    assert measurements[1].fat_percent == 18.5
    assert measurements[1].left_bicep_cm == 32


def test_hash_csv_content_is_stable_and_content_sensitive() -> None:
    assert hash_csv_content("a,b\n1,2\n") == hash_csv_content("a,b\n1,2\n")
    assert hash_csv_content("a,b\n1,2\n") != hash_csv_content("a,b\n1,3\n")


async def test_find_previous_import_is_none_before_any_import_is_recorded(db: AsyncSession) -> None:
    owner = await _create_user(db)
    assert await find_previous_import(db, owner.id, HevyImportKind.workouts, "some-hash") is None


async def test_record_import_makes_it_findable(db: AsyncSession) -> None:
    owner = await _create_user(db)
    await record_import(
        db,
        owner.id,
        HevyImportKind.workouts,
        "some-hash",
        "workout_data.csv",
        activities_created=3,
    )

    found = await find_previous_import(db, owner.id, HevyImportKind.workouts, "some-hash")
    assert found is not None
    assert found.filename == "workout_data.csv"
    assert found.activities_created == 3


async def test_find_previous_import_is_scoped_to_kind(db: AsyncSession) -> None:
    owner = await _create_user(db)
    await record_import(
        db, owner.id, HevyImportKind.measurements, "shared-hash", "x.csv", measurements_created=2
    )

    assert (
        await find_previous_import(db, owner.id, HevyImportKind.measurements, "shared-hash")
        is not None
    )
    assert await find_previous_import(db, owner.id, HevyImportKind.workouts, "shared-hash") is None


async def test_find_previous_import_is_scoped_to_owner(db: AsyncSession) -> None:
    owner = await _create_user(db, "owner@example.com")
    other = await _create_user(db, "other@example.com")
    await record_import(
        db, owner.id, HevyImportKind.workouts, "same-hash", "x.csv", activities_created=1
    )

    assert (
        await find_previous_import(db, owner.id, HevyImportKind.workouts, "same-hash") is not None
    )
    assert await find_previous_import(db, other.id, HevyImportKind.workouts, "same-hash") is None
