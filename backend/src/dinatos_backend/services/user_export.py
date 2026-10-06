"""One user's own data, out and back in (`GET /profile/export`, `POST
/profile/import`) -- see `docs/architecture/backend.md`'s "Backup and data
export" for the policy; this is the mechanics.

What travels: display settings, the exercises the user's routines/activities
refer to, their routines, activities and body measurements. Never ids, the
password hash, sessions, Hevy import records or the WorkoutX API key.

Exercises are a single global catalog with no owner, so "the user's custom
exercises" means "the exercises their data uses": on import each is matched
to an existing catalog entry by exact name (an existing entry is never
modified), and created as a custom exercise only when no such name exists.
Routines and activities are always created as rows owned by the caller, with
new ids.
"""

from datetime import UTC, datetime
from typing import Any, cast

from sqlalchemy import CursorResult, delete, exists, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from dinatos_backend.models.activity import Activity, ActivityExercise, ActivitySet
from dinatos_backend.models.exercise import Exercise, ExerciseMuscle
from dinatos_backend.models.hevy_import import HevyImportRecord
from dinatos_backend.models.measurement import BodyMeasurement
from dinatos_backend.models.routine import Routine, RoutineExercise, RoutineSet
from dinatos_backend.models.user import User
from dinatos_backend.schemas.backup import (
    ExportedActivity,
    ExportedActivityExercise,
    ExportedActivitySet,
    ExportedExercise,
    ExportedMeasurement,
    ExportedProfile,
    ExportedRoutine,
    ExportedRoutineExercise,
    ExportedRoutineSet,
    UserExport,
    UserImportCounts,
    UserImportMode,
    UserImportResult,
)
from dinatos_backend.services.backup import normalize_utc
from dinatos_backend.services.exercise import exercise_muscles
from dinatos_backend.services.profile import get_or_create_profile

_MEASUREMENT_FIELDS = tuple(ExportedMeasurement.model_fields.keys() - {"measured_at"})


class UserImportInvalidError(Exception):
    """The file is well-formed JSON of the right shape but refers to things
    it does not define (an unknown exercise, an unknown routine ref).
    """


async def export_user_data(db: AsyncSession, user: User, app_version: str) -> UserExport:
    profile = await get_or_create_profile(db, user.id)
    routines = list(
        await db.scalars(
            select(Routine)
            .options(selectinload(Routine.exercises).selectinload(RoutineExercise.sets))
            .where(Routine.owner_id == user.id)
            .order_by(Routine.name, Routine.id)
        )
    )
    activities = list(
        await db.scalars(
            select(Activity)
            .options(selectinload(Activity.exercises).selectinload(ActivityExercise.sets))
            .where(Activity.owner_id == user.id)
            .order_by(Activity.started_at, Activity.id)
        )
    )
    measurements = list(
        await db.scalars(
            select(BodyMeasurement)
            .where(BodyMeasurement.owner_id == user.id)
            .order_by(BodyMeasurement.measured_at, BodyMeasurement.id)
        )
    )
    exercise_ids = {item.exercise_id for routine in routines for item in routine.exercises} | {
        item.exercise_id for activity in activities for item in activity.exercises
    }
    exercises = list(
        await db.scalars(
            select(Exercise)
            .options(selectinload(Exercise.muscles))
            .where(Exercise.id.in_(exercise_ids))
            .order_by(Exercise.name)
        )
    )
    names = {exercise.id: exercise.name for exercise in exercises}
    refs = {routine.id: position for position, routine in enumerate(routines, start=1)}

    return UserExport(
        exported_at=datetime.now(UTC),
        app_version=app_version,
        profile=ExportedProfile(height_cm=profile.height_cm, unit_system=profile.unit_system),
        exercises=[
            ExportedExercise(
                name=exercise.name,
                tracks_weight=exercise.tracks_weight,
                tracks_reps=exercise.tracks_reps,
                tracks_distance=exercise.tracks_distance,
                tracks_duration=exercise.tracks_duration,
                equipment=exercise.equipment,
                primary_muscles=exercise.primary_muscles,
                secondary_muscles=exercise.secondary_muscles,
            )
            for exercise in exercises
        ],
        routines=[
            ExportedRoutine(
                ref=refs[routine.id],
                name=routine.name,
                description=routine.description,
                exercises=[
                    ExportedRoutineExercise(
                        exercise=names[item.exercise_id],
                        superset_group=item.superset_group,
                        notes=item.notes,
                        sets=[
                            ExportedRoutineSet(
                                set_type=s.set_type,
                                target_weight_kg=s.target_weight_kg,
                                target_reps=s.target_reps,
                                target_distance_km=s.target_distance_km,
                                target_duration_seconds=s.target_duration_seconds,
                            )
                            for s in item.sets
                        ],
                    )
                    for item in routine.exercises
                ],
            )
            for routine in routines
        ],
        activities=[
            ExportedActivity(
                title=activity.title,
                description=activity.description,
                started_at=normalize_utc(activity.started_at),
                ended_at=normalize_utc(activity.ended_at) if activity.ended_at else None,
                routine_ref=refs.get(activity.routine_id) if activity.routine_id else None,
                exercises=[
                    ExportedActivityExercise(
                        exercise=names[item.exercise_id],
                        superset_group=item.superset_group,
                        notes=item.notes,
                        sets=[
                            ExportedActivitySet(
                                set_type=s.set_type,
                                weight_kg=s.weight_kg,
                                reps=s.reps,
                                distance_km=s.distance_km,
                                duration_seconds=s.duration_seconds,
                                completed=s.completed,
                            )
                            for s in item.sets
                        ],
                    )
                    for item in activity.exercises
                ],
            )
            for activity in activities
        ],
        measurements=[
            ExportedMeasurement(
                measured_at=normalize_utc(m.measured_at),
                **{name: getattr(m, name) for name in _MEASUREMENT_FIELDS},
            )
            for m in measurements
        ],
    )


async def _delete_own_data(db: AsyncSession, owner_id: int) -> UserImportCounts:
    """Removes the caller's activities, routines and measurements (children
    first -- the schema's cascades are not relied on, sqlite has none).
    """
    routine_ids = select(Routine.id).where(Routine.owner_id == owner_id)
    routine_exercise_ids = select(RoutineExercise.id).where(
        RoutineExercise.routine_id.in_(routine_ids)
    )
    activity_ids = select(Activity.id).where(Activity.owner_id == owner_id)
    activity_exercise_ids = select(ActivityExercise.id).where(
        ActivityExercise.activity_id.in_(activity_ids)
    )
    statements = [
        delete(ActivitySet).where(ActivitySet.activity_exercise_id.in_(activity_exercise_ids)),
        delete(ActivityExercise).where(ActivityExercise.activity_id.in_(activity_ids)),
        delete(Activity).where(Activity.owner_id == owner_id),
        delete(RoutineSet).where(RoutineSet.routine_exercise_id.in_(routine_exercise_ids)),
        delete(RoutineExercise).where(RoutineExercise.routine_id.in_(routine_ids)),
        delete(Routine).where(Routine.owner_id == owner_id),
        delete(BodyMeasurement).where(BodyMeasurement.owner_id == owner_id),
    ]
    removed = [
        cast(
            "CursorResult[Any]",
            await db.execute(statement.execution_options(synchronize_session=False)),
        ).rowcount
        for statement in statements
    ]
    return UserImportCounts(activities=removed[2], routines=removed[5], measurements=removed[6])


async def clear_own_data(db: AsyncSession, user: User) -> UserImportCounts:
    """Wipes the caller's routines, activities, measurements and Hevy import
    records, plus every custom exercise that nothing else references any more.

    Exercises are shared by the whole server, not owned, so a custom exercise
    another account's routine or activity still uses is left alone (and the
    shipped catalog never is touched). Settings and the account itself stay.
    """
    deleted = await _delete_own_data(db, user.id)
    await db.execute(
        delete(HevyImportRecord)
        .where(HevyImportRecord.owner_id == user.id)
        .execution_options(synchronize_session=False)
    )
    unused = (
        select(Exercise.id)
        .where(Exercise.is_custom.is_(True))
        .where(~exists().where(RoutineExercise.exercise_id == Exercise.id))
        .where(~exists().where(ActivityExercise.exercise_id == Exercise.id))
    )
    unused_ids = list(await db.scalars(unused))
    if unused_ids:
        await db.execute(
            delete(ExerciseMuscle)
            .where(ExerciseMuscle.exercise_id.in_(unused_ids))
            .execution_options(synchronize_session=False)
        )
        await db.execute(
            delete(Exercise)
            .where(Exercise.id.in_(unused_ids))
            .execution_options(synchronize_session=False)
        )
    deleted.exercises = len(unused_ids)
    await db.commit()
    return deleted


def _used_exercise_names(document: UserExport) -> set[str]:
    return {item.exercise for routine in document.routines for item in routine.exercises} | {
        item.exercise for activity in document.activities for item in activity.exercises
    }


def _check_references(document: UserExport, known_exercises: set[str]) -> None:
    defined = {exercise.name for exercise in document.exercises}
    if len(defined) != len(document.exercises):
        raise UserImportInvalidError("'exercises' lists the same name more than once")
    refs = {routine.ref for routine in document.routines}
    if len(refs) != len(document.routines):
        raise UserImportInvalidError("'routines' reuses a ref")
    for name in _used_exercise_names(document):
        if name not in defined | known_exercises:
            raise UserImportInvalidError(
                f"exercise {name!r} is used but neither defined in "
                "'exercises' nor present on this server"
            )
    for activity in document.activities:
        if activity.routine_ref is not None and activity.routine_ref not in refs:
            raise UserImportInvalidError(f"activity {activity.title!r}: unknown routine_ref")


async def import_user_data(
    db: AsyncSession, user: User, document: UserExport, mode: UserImportMode
) -> UserImportResult:
    """Applies `document` to `user`'s own account in one transaction.

    `merge` (default) leaves everything already in the account alone and adds
    the rest: a routine counts as present when the caller has one with the
    same name, an activity when title and start time match, a measurement
    when its timestamp matches. Presence is judged against the account as it
    was *before* the import, so two same-named routines in the file both
    arrive, and importing the same file again adds nothing. `replace` first
    deletes the caller's routines, activities and measurements. Settings are
    applied in both modes. Everything is validated before anything is
    written.
    """
    names = {exercise.name for exercise in document.exercises} | _used_exercise_names(document)
    existing_exercises = {
        exercise.name: exercise.id
        for exercise in await db.scalars(select(Exercise).where(Exercise.name.in_(names)))
    }
    _check_references(document, set(existing_exercises))

    profile = await get_or_create_profile(db, user.id)  # commits only if it must create
    created, skipped = UserImportCounts(), UserImportCounts()
    deleted = UserImportCounts()
    if mode is UserImportMode.replace:
        deleted = await _delete_own_data(db, user.id)

    known_routines: dict[str, int] = {}
    known_activities: set[tuple[str, datetime]] = set()
    known_measurements: set[datetime] = set()
    if mode is UserImportMode.merge:
        for routine_id, routine_name in await db.execute(
            select(Routine.id, Routine.name)
            .where(Routine.owner_id == user.id)
            .order_by(Routine.id.desc())
        ):
            known_routines[routine_name] = routine_id  # lowest id wins
        for title, started_at in await db.execute(
            select(Activity.title, Activity.started_at).where(Activity.owner_id == user.id)
        ):
            known_activities.add((title, normalize_utc(started_at)))
        known_measurements = {
            normalize_utc(measured_at)
            for measured_at in await db.scalars(
                select(BodyMeasurement.measured_at).where(BodyMeasurement.owner_id == user.id)
            )
        }

    profile.height_cm = document.profile.height_cm
    profile.unit_system = document.profile.unit_system

    exercise_ids = dict(existing_exercises)
    for exercise in document.exercises:
        if exercise.name in exercise_ids:
            continue
        row = Exercise(
            name=exercise.name,
            tracks_weight=exercise.tracks_weight,
            tracks_reps=exercise.tracks_reps,
            tracks_distance=exercise.tracks_distance,
            tracks_duration=exercise.tracks_duration,
            is_custom=True,
            equipment=exercise.equipment,
            muscles=exercise_muscles(
                [m.value for m in exercise.primary_muscles],
                [m.value for m in exercise.secondary_muscles],
            ),
        )
        db.add(row)
        await db.flush()
        exercise_ids[exercise.name] = row.id
        created.exercises += 1

    routine_ids: dict[int, int] = {}
    for routine in document.routines:
        if routine.name in known_routines:
            routine_ids[routine.ref] = known_routines[routine.name]
            skipped.routines += 1
            continue
        new_routine = Routine(
            owner_id=user.id,
            name=routine.name,
            description=routine.description,
            exercises=[
                RoutineExercise(
                    exercise_id=exercise_ids[item.exercise],
                    superset_group=item.superset_group,
                    notes=item.notes,
                    position=position,
                    sets=[
                        RoutineSet(position=set_position, **s.model_dump())
                        for set_position, s in enumerate(item.sets)
                    ],
                )
                for position, item in enumerate(routine.exercises)
            ],
        )
        db.add(new_routine)
        await db.flush()
        routine_ids[routine.ref] = new_routine.id
        created.routines += 1

    for activity in document.activities:
        started_at = normalize_utc(activity.started_at)
        if (activity.title, started_at) in known_activities:
            skipped.activities += 1
            continue
        db.add(
            Activity(
                owner_id=user.id,
                routine_id=routine_ids[activity.routine_ref]
                if activity.routine_ref is not None
                else None,
                title=activity.title,
                description=activity.description,
                started_at=started_at,
                ended_at=normalize_utc(activity.ended_at) if activity.ended_at else None,
                exercises=[
                    ActivityExercise(
                        exercise_id=exercise_ids[item.exercise],
                        superset_group=item.superset_group,
                        notes=item.notes,
                        position=position,
                        sets=[
                            ActivitySet(position=set_position, **s.model_dump())
                            for set_position, s in enumerate(item.sets)
                        ],
                    )
                    for position, item in enumerate(activity.exercises)
                ],
            )
        )
        created.activities += 1

    for measurement in document.measurements:
        measured_at = normalize_utc(measurement.measured_at)
        if measured_at in known_measurements:
            skipped.measurements += 1
            continue
        db.add(
            BodyMeasurement(
                owner_id=user.id,
                **{**measurement.model_dump(), "measured_at": measured_at},
            )
        )
        created.measurements += 1

    await db.commit()
    return UserImportResult(mode=mode, created=created, skipped=skipped, deleted=deleted)
