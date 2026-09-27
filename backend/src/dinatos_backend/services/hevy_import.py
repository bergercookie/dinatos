"""Import Hevy's CSV exports (Settings -> Export routines/workout data).

Hevy's workout export is one row per set, in a flat CSV -- not the nested
workout/exercise/set shape our own API uses. A row's `set_index` restarts at
0 every time a new exercise instance begins within a workout (even for the
same exercise appearing twice, e.g. in two different supersets), which is
the only reliable signal for where one exercise instance ends and the next
begins; there is no explicit instance id to group on instead.

This is a one-shot migration path, not a sync: importing the same file twice
creates duplicate activities. `find_previous_import` lets a caller catch that
before it happens, by content hash rather than filename (Hevy names every
export the same thing, so the filename says nothing); it's on the caller
(see `api/routers/imports.py`) to decide what to do about a match, since
that's a per-request policy question, not an import-logic one.
"""

import csv
import hashlib
from dataclasses import dataclass, field
from datetime import datetime
from io import StringIO

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.activity import Activity, ActivityExercise, ActivitySet
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.models.hevy_import import HevyImportKind, HevyImportRecord
from dinatos_backend.models.measurement import BodyMeasurement
from dinatos_backend.models.workout import SetType
from dinatos_backend.schemas.imports import HevyMeasurementImportResult, HevyWorkoutImportResult

_TIMESTAMP_FORMAT = "%d %b %Y, %H:%M"

_MEASUREMENT_FIELDS = (
    "weight_kg",
    "fat_percent",
    "neck_cm",
    "shoulder_cm",
    "chest_cm",
    "left_bicep_cm",
    "right_bicep_cm",
    "left_forearm_cm",
    "right_forearm_cm",
    "abdomen_cm",
    "waist_cm",
    "hips_cm",
    "left_thigh_cm",
    "right_thigh_cm",
    "left_calf_cm",
    "right_calf_cm",
)


def _parse_timestamp(value: str) -> datetime:
    return datetime.strptime(value, _TIMESTAMP_FORMAT)


def _optional_float(value: str) -> float | None:
    return float(value) if value else None


def _optional_int(value: str) -> int | None:
    return int(float(value)) if value else None


@dataclass
class _SetRow:
    set_type: str
    weight_kg: float | None
    reps: int | None
    distance_km: float | None
    duration_seconds: int | None
    rpe: float | None


@dataclass
class _ExerciseInstance:
    exercise_title: str
    superset_id: int | None
    notes: str
    sets: list[_SetRow] = field(default_factory=list)


@dataclass
class _WorkoutGroup:
    title: str
    description: str
    started_at: datetime
    ended_at: datetime
    instances: list[_ExerciseInstance] = field(default_factory=list)


def _group_rows(rows: list[dict[str, str]]) -> list[_WorkoutGroup]:
    groups: dict[tuple[str, str, str], _WorkoutGroup] = {}
    order: list[tuple[str, str, str]] = []
    for row in rows:
        key = (row["title"], row["start_time"], row["end_time"])
        group = groups.get(key)
        if group is None:
            group = _WorkoutGroup(
                title=row["title"],
                description=row["description"],
                started_at=_parse_timestamp(row["start_time"]),
                ended_at=_parse_timestamp(row["end_time"]),
            )
            groups[key] = group
            order.append(key)

        if int(row["set_index"]) == 0 or not group.instances:
            group.instances.append(
                _ExerciseInstance(
                    exercise_title=row["exercise_title"],
                    superset_id=_optional_int(row["superset_id"]),
                    notes=row["exercise_notes"],
                )
            )
        group.instances[-1].sets.append(
            _SetRow(
                set_type=row["set_type"],
                weight_kg=_optional_float(row["weight_kg"]),
                reps=_optional_int(row["reps"]),
                distance_km=_optional_float(row["distance_km"]),
                duration_seconds=_optional_int(row["duration_seconds"]),
                rpe=_optional_float(row["rpe"]),
            )
        )

    return [groups[key] for key in order]


async def _get_or_create_exercises(
    db: AsyncSession, groups: list[_WorkoutGroup]
) -> tuple[dict[str, Exercise], int]:
    # An exercise's tracked-metric flags are inferred from every set imported
    # for it, so one heavy set with a weight doesn't get lost because an
    # earlier lookup only saw a bodyweight warmup.
    observed: dict[str, dict[str, bool]] = {}
    for group in groups:
        for instance in group.instances:
            flags = observed.setdefault(
                instance.exercise_title,
                dict.fromkeys(
                    ("tracks_weight", "tracks_reps", "tracks_distance", "tracks_duration"), False
                ),
            )
            for set_row in instance.sets:
                flags["tracks_weight"] |= set_row.weight_kg is not None
                flags["tracks_reps"] |= set_row.reps is not None
                flags["tracks_distance"] |= set_row.distance_km is not None
                flags["tracks_duration"] |= set_row.duration_seconds is not None

    created = 0
    by_name: dict[str, Exercise] = {}
    for name, flags in observed.items():
        result = await db.execute(select(Exercise).where(Exercise.name == name))
        exercise = result.scalar_one_or_none()
        if exercise is None:
            exercise = Exercise(name=name, **flags)
            db.add(exercise)
            created += 1
        by_name[name] = exercise
    await db.flush()
    return by_name, created


async def import_hevy_workouts(
    db: AsyncSession, owner_id: int, csv_text: str
) -> HevyWorkoutImportResult:
    rows = list(csv.DictReader(StringIO(csv_text)))
    groups = _group_rows(rows)
    exercise_by_name, exercises_created = await _get_or_create_exercises(db, groups)

    for group in groups:
        db.add(
            Activity(
                owner_id=owner_id,
                title=group.title,
                description=group.description or None,
                started_at=group.started_at,
                ended_at=group.ended_at,
                exercises=[
                    ActivityExercise(
                        exercise_id=exercise_by_name[instance.exercise_title].id,
                        position=position,
                        superset_group=instance.superset_id,
                        notes=instance.notes or None,
                        sets=[
                            ActivitySet(
                                position=set_position,
                                set_type=SetType(set_row.set_type),
                                weight_kg=set_row.weight_kg,
                                reps=set_row.reps,
                                distance_km=set_row.distance_km,
                                duration_seconds=set_row.duration_seconds,
                                rpe=set_row.rpe,
                            )
                            for set_position, set_row in enumerate(instance.sets)
                        ],
                    )
                    for position, instance in enumerate(group.instances)
                ],
            )
        )

    await db.commit()
    return HevyWorkoutImportResult(
        activities_created=len(groups), exercises_created=exercises_created
    )


async def import_hevy_measurements(
    db: AsyncSession, owner_id: int, csv_text: str
) -> HevyMeasurementImportResult:
    rows = list(csv.DictReader(StringIO(csv_text)))
    for row in rows:
        db.add(
            BodyMeasurement(
                owner_id=owner_id,
                measured_at=_parse_timestamp(row["date"]),
                **{name: _optional_float(row[name]) for name in _MEASUREMENT_FIELDS},
            )
        )
    await db.commit()
    return HevyMeasurementImportResult(measurements_created=len(rows))


def hash_csv_content(csv_text: str) -> str:
    return hashlib.sha256(csv_text.encode()).hexdigest()


async def find_previous_import(
    db: AsyncSession, owner_id: int, kind: HevyImportKind, content_hash: str
) -> HevyImportRecord | None:
    """The most recent prior import of this exact file content by this user,
    if any -- `None` means this exact file has never been imported by them
    as this `kind`. Scoped per user: someone else importing the same file
    content is not a duplicate of *this* user's import.
    """
    result = await db.execute(
        select(HevyImportRecord)
        .where(
            HevyImportRecord.owner_id == owner_id,
            HevyImportRecord.kind == kind,
            HevyImportRecord.content_hash == content_hash,
        )
        .order_by(HevyImportRecord.created_at.desc())
    )
    return result.scalars().first()


async def record_import(
    db: AsyncSession,
    owner_id: int,
    kind: HevyImportKind,
    content_hash: str,
    filename: str | None,
    *,
    activities_created: int | None = None,
    exercises_created: int | None = None,
    measurements_created: int | None = None,
) -> None:
    db.add(
        HevyImportRecord(
            owner_id=owner_id,
            kind=kind,
            content_hash=content_hash,
            filename=filename,
            activities_created=activities_created,
            exercises_created=exercises_created,
            measurements_created=measurements_created,
        )
    )
    await db.commit()
