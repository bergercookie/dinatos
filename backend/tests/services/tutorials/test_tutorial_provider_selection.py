from dinatos_backend.services import tutorials
from dinatos_backend.services.tutorials import get_tutorial_provider_for_key
from dinatos_backend.services.tutorials.cache import CachingTutorialProvider
from dinatos_backend.services.tutorials.fallback import FallbackTutorialProvider
from dinatos_backend.services.tutorials.free_exercise_db import FreeExerciseDbProvider
from dinatos_backend.services.tutorials.workoutx import WorkoutXProvider


def test_defaults_to_a_shared_free_exercise_db_provider_without_a_key() -> None:
    provider = get_tutorial_provider_for_key(None)

    assert isinstance(provider, CachingTutorialProvider)
    assert isinstance(provider._provider, FreeExerciseDbProvider)
    # A blank key counts as none, and the default is one process-wide
    # singleton so its cache persists across requests.
    assert get_tutorial_provider_for_key("") is provider


def test_each_key_gets_its_own_workoutx_provider_with_a_fallback() -> None:
    tutorials._user_providers.clear()

    a = get_tutorial_provider_for_key("key_a")

    assert isinstance(a, FallbackTutorialProvider)
    assert isinstance(a._primary, CachingTutorialProvider)
    assert isinstance(a._primary._provider, WorkoutXProvider)
    assert isinstance(a._fallback, FreeExerciseDbProvider)
    assert get_tutorial_provider_for_key("key_a") is a
    assert get_tutorial_provider_for_key("key_b") is not a
