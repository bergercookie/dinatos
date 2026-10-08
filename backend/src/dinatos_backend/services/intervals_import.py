"""One-time import of Intervals.icu activities (see `intervals_client`).

Like the Hevy import (`hevy_import`) this is a one-shot migration path, not a
sync: nothing is watched or pulled in the background, and the API key is used
for the request and never stored. What differs is how a second run is made
safe. A Hevy export is a file, so duplicates are caught by hashing its whole
content; an Intervals.icu activity has a stable id of its own, so each one is
remembered individually (`IntervalsImportedActivity`) and the same activity is
never imported twice -- not by importing the same selection again, nor by two
date ranges that overlap. As with Hevy, the caller must pass `force` to import
something again anyway, and a request that would hit a duplicate is rejected
whole (nothing written) rather than half-applied.

The other duplicate worth avoiding is a workout that is *also* in Hevy (Hevy
can sync to Intervals.icu): the preview flags any activity that starts within
`DUPLICATE_WINDOW` of one Dinatos already has, so the person can leave it out.
That is advisory only; the person decides what to import.

Mapping: each Intervals.icu activity becomes one Dinatos activity holding one
exercise named after its sport ("Run" -> "Running") with one set carrying the
duration and, where there is one, the distance. Intervals.icu has no
per-exercise strength data to map. Timestamps are `start_date_local`, stored
as given -- the same naive, wall-clock treatment as Hevy's CSV timestamps.
"""

import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.activity import Activity, ActivityExercise, ActivitySet
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.models.intervals_import import IntervalsImportedActivity
from dinatos_backend.schemas.imports import (
    ImportedExercise,
    IntervalsActivityPreview,
    IntervalsImportResult,
)
from dinatos_backend.services.backup import normalize_utc

DUPLICATE_WINDOW = timedelta(minutes=30)

_EXERCISE_NAMES = {
    "Run": "Running",
    "TrailRun": "Trail Running",
    "VirtualRun": "Virtual Running",
    "Ride": "Cycling",
    "VirtualRide": "Virtual Cycling",
    "GravelRide": "Gravel Cycling",
    "MountainBikeRide": "Mountain Biking",
    "Swim": "Swimming",
    "OpenWaterSwim": "Open Water Swimming",
    "Walk": "Walking",
    "Hike": "Hiking",
    "WeightTraining": "Weight Training",
}


class IntervalsImportConflictError(Exception):
    """Some selected activities were already imported (and `force` wasn't
    given), or another import of the same activities won a race with this
    one. Nothing was written. `already_imported` maps id -> when.
    """

    def __init__(self, already_imported: dict[str, datetime]) -> None:
        super().__init__("some of these activities were already imported")
        self.already_imported = already_imported


class IntervalsSelectionError(Exception):
    """Selected ids that can't be imported: not in the fetched window at all,
    or present but unimportable. Nothing was written.
    """

    def __init__(self, missing: list[str], unimportable: list[str]) -> None:
        super().__init__("some selected activities can't be imported")
        self.missing = missing
        self.unimportable = unimportable


@dataclass(frozen=True)
class _Candidate:
    id: str
    name: str
    type: str | None
    started_at: datetime
    ended_at: datetime | None
    duration_seconds: int | None
    distance_km: float | None
    description: str | None

    @property
    def exercise_name(self) -> str:
        if self.type is None:
            return "Workout"
        return _EXERCISE_NAMES.get(self.type) or re.sub(r"(?<=[a-z])(?=[A-Z])", " ", self.type)


@dataclass(frozen=True)
class _Unimportable:
    id: str
    name: str
    type: str | None
    reason: str


def _positive_int(value: Any) -> int | None:
    return round(value) if isinstance(value, int | float) and value > 0 else None


def _parse(raw: dict[str, Any]) -> _Candidate | _Unimportable | None:
    """`None` when the entry has no id at all -- nothing to key it on."""
    if raw.get("id") is None:
        return None
    activity_id = str(raw["id"])
    name = str(raw.get("name") or raw.get("type") or "Intervals.icu activity")[:200]
    kind = str(raw["type"]) if raw.get("type") else None
    try:
        started_at = datetime.fromisoformat(str(raw["start_date_local"])).replace(tzinfo=None)
    except (KeyError, ValueError):
        # Strava-sourced activities come back as a stub, with only a `_note`
        # saying Intervals.icu isn't allowed to share them.
        return _Unimportable(
            activity_id, name, kind, str(raw.get("_note") or "no readable start time")
        )

    duration = _positive_int(raw.get("moving_time")) or _positive_int(raw.get("elapsed_time"))
    elapsed = _positive_int(raw.get("elapsed_time")) or duration
    distance_m = raw.get("distance")
    description = str(raw["description"]).strip()[:2000] if raw.get("description") else None
    return _Candidate(
        id=activity_id,
        name=name,
        type=kind,
        started_at=started_at,
        ended_at=started_at + timedelta(seconds=elapsed) if elapsed else None,
        duration_seconds=duration,
        distance_km=round(distance_m / 1000, 3)
        if isinstance(distance_m, int | float) and distance_m > 0
        else None,
        description=description or None,
    )


async def _already_imported(
    db: AsyncSession, owner_id: int, intervals_ids: list[str]
) -> dict[str, datetime]:
    """Id -> import time, for those still present: a row whose activity has
    since been deleted doesn't count.
    """
    rows = await db.execute(
        select(IntervalsImportedActivity.intervals_id, IntervalsImportedActivity.created_at)
        .join(Activity, Activity.id == IntervalsImportedActivity.activity_id)
        .where(
            IntervalsImportedActivity.owner_id == owner_id,
            IntervalsImportedActivity.intervals_id.in_(intervals_ids),
        )
    )
    return {intervals_id: created_at for intervals_id, created_at in rows}


async def _possible_duplicates(
    db: AsyncSession, owner_id: int, candidates: list[_Candidate]
) -> dict[str, str]:
    """Candidate id -> title of an existing activity starting within
    `DUPLICATE_WINDOW` of it.
    """
    if not candidates:
        return {}
    starts = [normalize_utc(c.started_at) for c in candidates]
    rows = await db.execute(
        select(Activity.title, Activity.started_at).where(
            Activity.owner_id == owner_id,
            Activity.started_at >= min(starts) - DUPLICATE_WINDOW,
            Activity.started_at <= max(starts) + DUPLICATE_WINDOW,
        )
    )
    existing = [(title, normalize_utc(started_at)) for title, started_at in rows]
    found: dict[str, str] = {}
    for candidate, start in zip(candidates, starts, strict=True):
        for title, existing_start in existing:
            if abs(existing_start - start) <= DUPLICATE_WINDOW:
                found[candidate.id] = title
                break
    return found


async def build_preview(
    db: AsyncSession, owner_id: int, raw_activities: list[dict[str, Any]]
) -> list[IntervalsActivityPreview]:
    """Everything fetched, newest first, annotated so the person can choose."""
    parsed = [p for raw in raw_activities if (p := _parse(raw)) is not None]
    candidates = [p for p in parsed if isinstance(p, _Candidate)]
    imported = await _already_imported(db, owner_id, [p.id for p in parsed])
    # An activity already imported matches its own Dinatos copy, which says nothing new.
    fresh = [c for c in candidates if c.id not in imported]
    duplicates = await _possible_duplicates(db, owner_id, fresh)

    previews: list[IntervalsActivityPreview] = []
    for item in parsed:
        if isinstance(item, _Unimportable):
            previews.append(
                IntervalsActivityPreview(
                    id=item.id,
                    name=item.name,
                    type=item.type,
                    importable=False,
                    unimportable_reason=item.reason,
                )
            )
            continue
        previews.append(
            IntervalsActivityPreview(
                id=item.id,
                name=item.name,
                type=item.type,
                started_at=item.started_at,
                duration_seconds=item.duration_seconds,
                distance_km=item.distance_km,
                already_imported=item.id in imported,
                imported_at=imported.get(item.id),
                possible_duplicate_of=duplicates.get(item.id),
            )
        )
    # Unimportable stubs have no date and sink to the end.
    previews.sort(key=lambda p: p.started_at or datetime.min, reverse=True)
    return previews


async def _get_or_create_exercises(
    db: AsyncSession, candidates: list[_Candidate]
) -> tuple[dict[str, Exercise], list[ImportedExercise]]:
    distance_tracked = {c.exercise_name: False for c in candidates}
    for c in candidates:
        distance_tracked[c.exercise_name] |= c.distance_km is not None

    by_name: dict[str, Exercise] = {}
    created: list[Exercise] = []
    for name, tracks_distance in distance_tracked.items():
        # A name that already exists (the person's own, or a built-in) wins.
        exercise = await db.scalar(select(Exercise).where(Exercise.name == name))
        if exercise is None:
            exercise = Exercise(
                name=name,
                tracks_weight=False,
                tracks_reps=False,
                tracks_distance=tracks_distance,
                tracks_duration=True,
            )
            db.add(exercise)
            created.append(exercise)
        by_name[name] = exercise
    await db.flush()
    return by_name, [ImportedExercise(id=e.id, name=e.name) for e in created]


async def import_intervals_activities(
    db: AsyncSession,
    owner_id: int,
    raw_activities: list[dict[str, Any]],
    activity_ids: list[str],
    *,
    force: bool = False,
) -> IntervalsImportResult:
    """Import the selected ids out of `raw_activities` in one transaction.

    Raises `IntervalsSelectionError` for ids that aren't importable and
    `IntervalsImportConflictError` for ones already imported (unless `force`);
    in both cases nothing has been written.
    """
    selected = list(dict.fromkeys(activity_ids))
    parsed = {p.id: p for raw in raw_activities if (p := _parse(raw)) is not None}
    missing = [i for i in selected if i not in parsed]
    unimportable = [i for i in selected if isinstance(parsed.get(i), _Unimportable)]
    if missing or unimportable:
        raise IntervalsSelectionError(missing, unimportable)

    candidates = sorted(
        (p for i in selected if isinstance(p := parsed[i], _Candidate)),
        key=lambda c: c.started_at,
    )
    previous = await _already_imported(db, owner_id, selected)
    if previous and not force:
        raise IntervalsImportConflictError(previous)

    exercise_by_name, created_exercises = await _get_or_create_exercises(db, candidates)
    activities: dict[str, Activity] = {}
    for candidate in candidates:
        activity = Activity(
            owner_id=owner_id,
            title=candidate.name,
            description=candidate.description,
            started_at=candidate.started_at,
            ended_at=candidate.ended_at,
            exercises=[
                ActivityExercise(
                    exercise_id=exercise_by_name[candidate.exercise_name].id,
                    position=0,
                    superset_group=None,
                    sets=[
                        ActivitySet(
                            position=0,
                            distance_km=candidate.distance_km,
                            duration_seconds=candidate.duration_seconds,
                        )
                    ],
                )
            ],
        )
        db.add(activity)
        activities[candidate.id] = activity
    await db.flush()

    # A forced re-import (or one over a deleted activity) repoints the
    # existing row instead of adding a second one for the same id.
    rows = await db.scalars(
        select(IntervalsImportedActivity).where(
            IntervalsImportedActivity.owner_id == owner_id,
            IntervalsImportedActivity.intervals_id.in_(selected),
        )
    )
    mapping = {row.intervals_id: row for row in rows}
    for candidate in candidates:
        row = mapping.get(candidate.id)
        if row is None:
            row = IntervalsImportedActivity(owner_id=owner_id, intervals_id=candidate.id)
            db.add(row)
        row.activity_id = activities[candidate.id].id
        row.started_at = candidate.started_at

    try:
        await db.commit()
    except IntegrityError as error:
        # Two requests importing the same activity at once: the unique
        # (owner, id) constraint lets exactly one through.
        await db.rollback()
        raise IntervalsImportConflictError({}) from error
    return IntervalsImportResult(
        activities_created=len(candidates),
        exercises_created=len(created_exercises),
        created_exercises=created_exercises,
    )
