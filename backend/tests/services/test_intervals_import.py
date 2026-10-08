from datetime import datetime, timedelta
from typing import Any

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.activity import Activity
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.models.intervals_import import IntervalsImportedActivity
from dinatos_backend.models.user import User
from dinatos_backend.services.intervals_import import (
    IntervalsImportConflictError,
    IntervalsSelectionError,
    build_preview,
    import_intervals_activities,
)

RUN: dict[str, Any] = {
    "id": "i100",
    "name": "Morning run",
    "type": "Run",
    "start_date_local": "2026-03-01T07:30:00",
    "moving_time": 1800,
    "elapsed_time": 1900,
    "distance": 5200.0,
    "description": "  felt good ",
}
RIDE: dict[str, Any] = {
    "id": 101,  # older activities carry a bare number
    "name": "Commute",
    "type": "VirtualRide",
    "start_date_local": "2026-03-02T18:00:00",
    "moving_time": 1200,
}
STRAVA_STUB: dict[str, Any] = {"id": "i102", "_note": "STRAVA activities are not available"}


async def _user(db: AsyncSession, email: str = "owner@example.com") -> User:
    user = User(email=email, password_hash="not-a-real-hash")
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


async def _count(db: AsyncSession, model: type) -> int:
    return await db.scalar(select(func.count()).select_from(model)) or 0


async def test_import_maps_an_activity_to_one_exercise_with_one_set(db: AsyncSession) -> None:
    owner = await _user(db)

    result = await import_intervals_activities(db, owner.id, [RUN, RIDE], ["i100", "101"])

    assert (result.activities_created, result.exercises_created) == (2, 2)
    assert {e.name for e in result.created_exercises} == {"Running", "Virtual Cycling"}
    activities = (await db.scalars(select(Activity).order_by(Activity.started_at))).all()
    run = activities[0]
    assert (run.title, run.description, run.owner_id) == ("Morning run", "felt good", owner.id)
    assert run.started_at.replace(tzinfo=None) == datetime(2026, 3, 1, 7, 30)
    # Ends after the *elapsed* time, while the set carries the moving time.
    assert run.ended_at is not None
    assert run.ended_at.replace(tzinfo=None) == datetime(2026, 3, 1, 7, 30) + timedelta(
        seconds=1900
    )
    await db.refresh(run, ["exercises"])
    (activity_exercise,) = run.exercises
    (only_set,) = activity_exercise.sets
    assert (only_set.distance_km, only_set.duration_seconds) == (5.2, 1800)
    running = await db.scalar(select(Exercise).where(Exercise.name == "Running"))
    assert running is not None
    assert (running.tracks_distance, running.tracks_duration, running.tracks_reps) == (
        True,
        True,
        False,
    )
    # No distance anywhere for cycling -> not tracked.
    cycling = await db.scalar(select(Exercise).where(Exercise.name == "Virtual Cycling"))
    assert cycling is not None
    assert cycling.tracks_distance is False
    ride = activities[1]
    assert ride.ended_at is not None  # falls back to the moving time
    assert await _count(db, IntervalsImportedActivity) == 2


@pytest.mark.parametrize(
    ("kind", "name"),
    [
        (None, "Workout"),
        ("Yoga", "Yoga"),
        ("NordicSki", "Nordic Ski"),
        ("Run", "Running"),
    ],
)
async def test_exercise_names_from_sport_types(
    db: AsyncSession, kind: str | None, name: str
) -> None:
    owner = await _user(db)
    raw = {"id": "i1", "start_date_local": "2026-03-01T07:30:00", "type": kind}

    result = await import_intervals_activities(db, owner.id, [raw], ["i1"])

    assert [e.name for e in result.created_exercises] == [name]


async def test_an_existing_exercise_of_that_name_is_reused(db: AsyncSession) -> None:
    owner = await _user(db)
    db.add(Exercise(name="Running", tracks_weight=False, tracks_reps=False))
    await db.commit()

    result = await import_intervals_activities(db, owner.id, [RUN], ["i100"])

    assert (result.activities_created, result.exercises_created) == (1, 0)
    assert await _count(db, Exercise) == 1


async def test_sparse_activities_import_with_defaults(db: AsyncSession) -> None:
    owner = await _user(db)
    bare = {
        "id": "i7",
        "start_date_local": "2026-03-01T07:30:00+00:00",
        "distance": 0,
        "moving_time": 0,
    }

    await import_intervals_activities(db, owner.id, [bare], ["i7"])

    activity = await db.scalar(select(Activity))
    assert activity is not None
    assert (activity.title, activity.ended_at, activity.description) == (
        "Intervals.icu activity",
        None,
        None,
    )
    assert activity.started_at.replace(tzinfo=None) == datetime(2026, 3, 1, 7, 30)


async def test_importing_the_same_activities_twice_is_rejected_and_writes_nothing(
    db: AsyncSession,
) -> None:
    owner = await _user(db)
    await import_intervals_activities(db, owner.id, [RUN], ["i100"])

    # One new, one already imported: the whole request is refused.
    with pytest.raises(IntervalsImportConflictError) as caught:
        await import_intervals_activities(db, owner.id, [RUN, RIDE], ["i100", "101"])

    assert list(caught.value.already_imported) == ["i100"]
    assert await _count(db, Activity) == 1
    assert await _count(db, IntervalsImportedActivity) == 1


async def test_force_imports_again_and_repoints_the_record(db: AsyncSession) -> None:
    owner = await _user(db)
    await import_intervals_activities(db, owner.id, [RUN], ["i100"])

    result = await import_intervals_activities(db, owner.id, [RUN], ["i100"], force=True)

    assert (result.activities_created, result.exercises_created) == (1, 0)
    assert await _count(db, Activity) == 2
    (record,) = (await db.scalars(select(IntervalsImportedActivity))).all()
    newest = await db.scalar(select(Activity).order_by(Activity.id.desc()))
    assert newest is not None
    assert record.activity_id == newest.id


async def test_a_deleted_import_can_be_imported_again_without_force(db: AsyncSession) -> None:
    owner = await _user(db)
    await import_intervals_activities(db, owner.id, [RUN], ["i100"])
    activity = await db.scalar(select(Activity))
    assert activity is not None
    await db.delete(activity)
    await db.commit()
    # The stale record doesn't count as "already imported" in the preview either.
    (preview,) = await build_preview(db, owner.id, [RUN])
    assert preview.already_imported is False

    result = await import_intervals_activities(db, owner.id, [RUN], ["i100"])

    assert result.activities_created == 1
    (record,) = (await db.scalars(select(IntervalsImportedActivity))).all()
    assert record.activity_id == (await db.scalar(select(Activity.id)))
    assert await _count(db, IntervalsImportedActivity) == 1


async def test_imports_are_scoped_per_user(db: AsyncSession) -> None:
    alice = await _user(db, "alice@example.com")
    bob = await _user(db, "bob@example.com")
    await import_intervals_activities(db, alice.id, [RUN], ["i100"])

    result = await import_intervals_activities(db, bob.id, [RUN], ["i100"])

    assert result.activities_created == 1


async def test_a_selection_naming_missing_or_unimportable_ids_is_refused(db: AsyncSession) -> None:
    owner = await _user(db)

    with pytest.raises(IntervalsSelectionError) as caught:
        await import_intervals_activities(
            db, owner.id, [RUN, STRAVA_STUB], ["i100", "i102", "nope"]
        )

    assert (caught.value.missing, caught.value.unimportable) == (["nope"], ["i102"])
    assert await _count(db, Activity) == 0


async def test_duplicate_ids_in_a_selection_import_once(db: AsyncSession) -> None:
    owner = await _user(db)

    result = await import_intervals_activities(db, owner.id, [RUN], ["i100", "i100"])

    assert result.activities_created == 1


async def test_losing_a_race_to_a_concurrent_import_is_a_conflict(
    db: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    owner = await _user(db)

    async def lose_the_race() -> None:
        # What Postgres raises at commit when another request's transaction
        # inserted the same (owner, intervals id) first.
        raise IntegrityError("INSERT", {}, Exception("unique violation"))

    monkeypatch.setattr(db, "commit", lose_the_race)

    with pytest.raises(IntervalsImportConflictError):
        await import_intervals_activities(db, owner.id, [RUN], ["i100"])

    # The failed attempt left nothing behind and the session is still usable.
    assert await _count(db, Activity) == 0


async def test_preview_flags_imported_unimportable_and_possibly_duplicated(
    db: AsyncSession,
) -> None:
    owner = await _user(db)
    other = await _user(db, "other@example.com")
    await import_intervals_activities(db, owner.id, [RUN], ["i100"])
    # Hevy logged the ride 20 minutes after Intervals.icu says it started;
    # another account's activity at the same time must not count.
    db.add(Activity(owner_id=owner.id, title="Hevy ride", started_at=datetime(2026, 3, 2, 18, 20)))
    db.add(Activity(owner_id=other.id, title="Not mine", started_at=datetime(2026, 3, 2, 18, 0)))
    far = {**RIDE, "id": "i103", "start_date_local": "2026-03-05T09:00:00"}
    db.add(Activity(owner_id=owner.id, title="Too far", started_at=datetime(2026, 3, 5, 10, 0)))
    await db.commit()

    previews = await build_preview(
        db, owner.id, [RUN, RIDE, STRAVA_STUB, far, {"name": "no id at all"}]
    )

    assert [p.id for p in previews] == ["i103", "101", "i100", "i102"]  # newest first, stub last
    by_id = {p.id: p for p in previews}
    assert by_id["i100"].already_imported is True
    assert by_id["i100"].imported_at is not None
    assert by_id["i100"].possible_duplicate_of is None  # its own copy is not a "duplicate"
    assert by_id["i100"].distance_km == 5.2
    assert by_id["i100"].duration_seconds == 1800
    assert by_id["101"].possible_duplicate_of == "Hevy ride"
    assert by_id["101"].already_imported is False
    assert by_id["i103"].possible_duplicate_of is None
    stub = by_id["i102"]
    assert (stub.importable, stub.started_at) == (False, None)
    assert stub.unimportable_reason == "STRAVA activities are not available"


async def test_preview_of_nothing_is_empty(db: AsyncSession) -> None:
    owner = await _user(db)

    assert await build_preview(db, owner.id, []) == []
