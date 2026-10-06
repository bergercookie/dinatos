"""A standard starting catalog, seeded once into a brand new instance.

The catalog (name + which of weight/reps/distance/duration a set logged
against it would track) comes from the same vendored dataset
`services.tutorials.free_exercise_db` reads for tutorial content --
`data/free_exercise_db.json`, see `data/NOTICE.md` for provenance. Reusing
it here means an instance's exercise names already match that dataset's
own exactly, so its tutorial lookups (by name) hit on the very first try
instead of needing any fuzzy matching.
"""

from collections.abc import Iterator
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.config import get_settings
from dinatos_backend.models.exercise import Equipment, Exercise, ExerciseMuscle, MuscleGroup
from dinatos_backend.services.tutorials.free_exercise_db import load_free_exercise_db


def _infer_tracking(category: str, force: str | None) -> tuple[bool, bool, bool, bool]:
    """(tracks_weight, tracks_reps, tracks_distance, tracks_duration), guessed
    from the dataset's own `category`/`force` fields -- these flags are
    advisory UI metadata (see `models.exercise.Exercise`'s class doc), not a
    hard constraint, so an imperfect guess for an unusual entry is fine.
    """
    if category == "cardio":
        return (False, False, True, True)
    if category == "stretching" or force == "static":
        return (False, False, False, True)
    return (True, True, False, False)


def _normalize(raw: str) -> str:
    """The dataset's own spelling ("e-z curl bar", "lower back") to the
    `MuscleGroup`/`Equipment` enum member spelling (spaces/hyphens can't
    appear in a Python identifier) -- see those enums' docstrings.
    """
    return raw.strip().lower().replace(" ", "_").replace("-", "_")


def _equipment(raw: str | None) -> Equipment | None:
    return Equipment(_normalize(raw)) if raw else None


def _muscles(raw: list[str]) -> list[MuscleGroup]:
    return [MuscleGroup(_normalize(entry)) for entry in raw]


def exercise_muscles(primary_raw: list[str], secondary_raw: list[str]) -> list[ExerciseMuscle]:
    """A handful of the vendored dataset's own entries list the same muscle
    in both `primaryMuscles` and `secondaryMuscles` (e.g. "Clean and
    Press"'s `shoulders`) -- a dataset quirk, not a meaningful "trains this
    muscle twice", and `ExerciseMuscle`'s (exercise, muscle) uniqueness
    means inserting both would violate it. Primary wins on overlap, so a
    muscle this exercise most works never gets demoted to secondary.
    """
    primary_muscles = _muscles(primary_raw)
    secondary_muscles = [m for m in _muscles(secondary_raw) if m not in primary_muscles]
    return [ExerciseMuscle(muscle=muscle, is_primary=True) for muscle in primary_muscles] + [
        ExerciseMuscle(muscle=muscle, is_primary=False) for muscle in secondary_muscles
    ]


def _default_exercises() -> Iterator[dict[str, Any]]:
    for entry in load_free_exercise_db():
        tracks_weight, tracks_reps, tracks_distance, tracks_duration = _infer_tracking(
            entry["category"], entry.get("force")
        )
        yield {
            "name": entry["name"],
            "tracks_weight": tracks_weight,
            "tracks_reps": tracks_reps,
            "tracks_distance": tracks_distance,
            "tracks_duration": tracks_duration,
            "is_custom": False,
            "equipment": _equipment(entry.get("equipment")),
            "muscles": exercise_muscles(entry["primaryMuscles"], entry["secondaryMuscles"]),
        }


def catalog_for_local_mode() -> list[dict[str, Any]]:
    """The built-in catalog as plain JSON, in seeding order, for the app's
    no-server mode (`frontend/assets/exercise_catalog.json`, written by
    `scripts/generate_exercise_catalog.py`). Same names, tracking flags,
    equipment and muscles the server seeds; no tutorial text.
    """
    return [
        {
            "name": fields["name"],
            "tracks_weight": fields["tracks_weight"],
            "tracks_reps": fields["tracks_reps"],
            "tracks_distance": fields["tracks_distance"],
            "tracks_duration": fields["tracks_duration"],
            "equipment": fields["equipment"].value if fields["equipment"] else None,
            "primary_muscles": [m.muscle.value for m in fields["muscles"] if m.is_primary],
            "secondary_muscles": [m.muscle.value for m in fields["muscles"] if not m.is_primary],
        }
        for fields in _default_exercises()
    ]


async def bootstrap_default_exercises(db: AsyncSession) -> None:
    """Seeds the vendored catalog into a brand new instance's empty
    `exercises` table -- a no-op the moment any exercise exists, whether
    from an earlier run of this same seeding or something a person added
    or imported themselves. That guard is table-wide, not per-name, on
    purpose: once someone's deleted a seeded exercise they didn't want,
    it should stay gone, not reappear on the next restart.
    """
    if not get_settings().seed_default_exercises:
        return

    count = await db.execute(select(func.count()).select_from(Exercise))
    if count.scalar_one() > 0:
        return

    db.add_all(Exercise(**fields) for fields in _default_exercises())
    await db.commit()
