import pytest

from dinatos_backend.config import Settings
from dinatos_backend.services import tutorials
from dinatos_backend.services.tutorials import get_tutorial_provider
from dinatos_backend.services.tutorials.cache import CachingTutorialProvider
from dinatos_backend.services.tutorials.free_exercise_db import FreeExerciseDbProvider
from dinatos_backend.services.tutorials.workoutx import WorkoutXProvider


@pytest.fixture(autouse=True)
def _clear_provider_cache() -> None:
    # `get_tutorial_provider` is a process-wide `lru_cache` singleton on
    # purpose (see its own docstring) -- exactly what a test needs to
    # reset between runs, unlike production.
    get_tutorial_provider.cache_clear()


def test_defaults_to_free_exercise_db_without_an_api_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tutorials, "get_settings", lambda: Settings(workoutx_api_key=None))

    provider = get_tutorial_provider()

    assert isinstance(provider, CachingTutorialProvider)
    assert isinstance(provider._provider, FreeExerciseDbProvider)


def test_uses_workoutx_when_an_api_key_is_configured(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tutorials, "get_settings", lambda: Settings(workoutx_api_key="wx_secret"))

    provider = get_tutorial_provider()

    assert isinstance(provider._provider, WorkoutXProvider)


def test_is_a_singleton_across_calls(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(tutorials, "get_settings", lambda: Settings(workoutx_api_key=None))

    assert get_tutorial_provider() is get_tutorial_provider()
