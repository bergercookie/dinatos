from dinatos_backend.services.tutorials.base import ExerciseTutorial
from dinatos_backend.services.tutorials.cache import CachingTutorialProvider

_TUTORIAL = ExerciseTutorial(
    source="fake",
    gif_urls=["https://example.com/a.gif"],
    instructions=["Do the thing."],
    equipment=None,
    primary_muscles=["abs"],
    secondary_muscles=[],
)


class _CountingProvider:
    """A fake `TutorialProvider` that counts how many times it was
    actually asked -- what proves the cache is doing its job.
    """

    def __init__(self, result: ExerciseTutorial | None) -> None:
        self.result = result
        self.calls = 0

    async def get_tutorial(self, _exercise_name: str) -> ExerciseTutorial | None:
        self.calls += 1
        return self.result


async def test_repeated_lookups_of_the_same_exercise_hit_the_provider_once() -> None:
    provider = _CountingProvider(_TUTORIAL)
    cache = CachingTutorialProvider(provider)

    first = await cache.get_tutorial("Squat (Barbell)")
    second = await cache.get_tutorial("Squat (Barbell)")

    assert first == _TUTORIAL
    assert second == _TUTORIAL
    assert provider.calls == 1


async def test_lookups_are_case_insensitive_for_caching_purposes() -> None:
    provider = _CountingProvider(_TUTORIAL)
    cache = CachingTutorialProvider(provider)

    await cache.get_tutorial("Squat (Barbell)")
    await cache.get_tutorial("squat (barbell)")

    assert provider.calls == 1


async def test_a_not_found_result_is_cached_too() -> None:
    """Not just successful lookups -- an exercise the provider has
    nothing for shouldn't be asked about again either.
    """
    provider = _CountingProvider(None)
    cache = CachingTutorialProvider(provider)

    await cache.get_tutorial("Not A Real Exercise")
    await cache.get_tutorial("Not A Real Exercise")

    assert provider.calls == 1


async def test_different_exercises_are_cached_independently() -> None:
    provider = _CountingProvider(_TUTORIAL)
    cache = CachingTutorialProvider(provider)

    await cache.get_tutorial("Squat (Barbell)")
    await cache.get_tutorial("Bench Press (Barbell)")

    assert provider.calls == 2
