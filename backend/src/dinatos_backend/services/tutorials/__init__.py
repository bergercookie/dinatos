"""Exercise tutorial lookups (a GIF plus instructions/muscles/equipment),
from whichever provider applies -- the bundled, public-domain
`free-exercise-db` dataset by default, or WorkoutX for a user who has saved
their own API key. See `base.py` for the shared contract,
`free_exercise_db.py`/`workoutx.py` for the two providers, and `cache.py`
for the in-memory caching every provider is wrapped in.
"""

from functools import lru_cache

from dinatos_backend.services.tutorials.base import ExerciseTutorial, TutorialProvider
from dinatos_backend.services.tutorials.cache import CachingTutorialProvider
from dinatos_backend.services.tutorials.fallback import FallbackTutorialProvider
from dinatos_backend.services.tutorials.free_exercise_db import FreeExerciseDbProvider
from dinatos_backend.services.tutorials.workoutx import WorkoutXProvider

__all__ = ["ExerciseTutorial", "TutorialProvider", "get_tutorial_provider_for_key"]


@lru_cache
def _default_provider() -> TutorialProvider:
    # A process-wide singleton, which is what makes the
    # `CachingTutorialProvider` actually cache across requests rather than
    # start empty on every call.
    return CachingTutorialProvider(FreeExerciseDbProvider())


_user_providers: dict[str, TutorialProvider] = {}


def get_tutorial_provider_for_key(api_key: str | None) -> TutorialProvider:
    """WorkoutX with a user's own API key (`UserProfile.workoutx_api_key`),
    the bundled free-exercise-db dataset if they have none. One cached
    provider per distinct key, so each key's in-memory cache (and its
    quota) stays its own. WorkoutX is wrapped so the bundled dataset
    answers whenever it fails (a bad key, an outage) or has no match; the
    cache sits *inside* that fallback, around WorkoutX only, so a failure
    is never cached and fixing the key takes effect on the next request.
    """
    if not api_key:
        return _default_provider()
    if api_key not in _user_providers:
        workoutx = CachingTutorialProvider(WorkoutXProvider(api_key))
        _user_providers[api_key] = FallbackTutorialProvider(workoutx, FreeExerciseDbProvider())
    return _user_providers[api_key]
