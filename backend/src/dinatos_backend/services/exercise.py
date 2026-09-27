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
from dinatos_backend.models.exercise import Exercise
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
        }


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
