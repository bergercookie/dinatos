"""The default, always-available tutorial provider: the vendored public-
domain dataset from https://github.com/yuhonas/free-exercise-db (see
`data/NOTICE.md` for provenance and license). Reads from disk -- no
network call, no API key, no rate limit, and (per that project's
Unlicense) no restriction on bulk use, unlike `workoutx.py`.
"""

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from dinatos_backend.services.tutorials.base import ExerciseTutorial

_DATA_PATH = Path(__file__).resolve().parent.parent.parent / "data" / "free_exercise_db.json"
_IMAGE_BASE_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"


@lru_cache
def load_free_exercise_db() -> tuple[dict[str, Any], ...]:
    """The vendored dataset, parsed once and cached for the process's
    lifetime -- it's read-only, bundled data, not something that changes
    between calls. Also what `services.exercise.bootstrap_default_exercises`
    seeds the `exercises` table from.
    """
    return tuple(json.loads(_DATA_PATH.read_text()))


@lru_cache
def _by_name() -> dict[str, dict[str, Any]]:
    return {entry["name"].casefold(): entry for entry in load_free_exercise_db()}


class FreeExerciseDbProvider:
    """Looks a name up in the vendored dataset -- exact match only (case-
    insensitive): every exercise in this instance's catalog was itself
    seeded from this same dataset, so a lookup by an unmodified name
    always hits; only a person's own renamed or custom exercise misses.
    """

    async def get_tutorial(self, exercise_name: str) -> ExerciseTutorial | None:
        entry = _by_name().get(exercise_name.casefold())
        if entry is None:
            return None
        return ExerciseTutorial(
            source="free_exercise_db",
            gif_urls=[_IMAGE_BASE_URL + image for image in entry["images"]],
            instructions=entry["instructions"],
            equipment=entry.get("equipment"),
            primary_muscles=entry["primaryMuscles"],
            secondary_muscles=entry["secondaryMuscles"],
        )
