"""Exercise tutorial lookups (a GIF plus instructions/muscles/equipment),
from whichever provider is active -- the bundled, public-domain
`free-exercise-db` dataset by default, or WorkoutX if a homelab admin has
opted in with their own API key. See `base.py` for the shared contract,
`free_exercise_db.py`/`workoutx.py` for the two providers, and `cache.py`
for the in-memory caching every provider is wrapped in.
"""

from functools import lru_cache

from dinatos_backend.config import get_settings
from dinatos_backend.services.tutorials.base import ExerciseTutorial, TutorialProvider
from dinatos_backend.services.tutorials.cache import CachingTutorialProvider
from dinatos_backend.services.tutorials.fallback import FallbackTutorialProvider
from dinatos_backend.services.tutorials.free_exercise_db import FreeExerciseDbProvider
from dinatos_backend.services.tutorials.workoutx import WorkoutXProvider

__all__ = ["ExerciseTutorial", "TutorialProvider", "get_tutorial_provider"]


@lru_cache
def get_tutorial_provider() -> TutorialProvider:
    """WorkoutX if a homelab admin has opted in with their own API key
    (`Settings.workoutx_api_key`), the bundled free-exercise-db dataset
    otherwise -- that key's mere presence is the only toggle, the same
    pattern `Settings.admin_email`/`admin_password` already use. WorkoutX
    is wrapped so the bundled dataset answers whenever it fails (a bad
    key, an outage) or has no match. The cache sits *inside* that
    fallback, around WorkoutX only: a failure is never cached, so fixing
    the key takes effect on the next request without a restart. `lru_cache`
    makes this a process-wide singleton, which is what makes the
    `CachingTutorialProvider` actually cache across requests rather than
    start empty on every call.
    """
    settings = get_settings()
    free = FreeExerciseDbProvider()
    if settings.workoutx_api_key:
        workoutx = CachingTutorialProvider(WorkoutXProvider(settings.workoutx_api_key))
        return FallbackTutorialProvider(workoutx, free)
    return CachingTutorialProvider(free)
