from dinatos_backend.services.tutorials.base import ExerciseTutorial
from dinatos_backend.services.tutorials.cache import CachingTutorialProvider
from dinatos_backend.services.tutorials.fallback import FallbackTutorialProvider


def _tutorial(source: str) -> ExerciseTutorial:
    return ExerciseTutorial(
        source=source,
        gif_urls=[],
        instructions=[],
        equipment=None,
        primary_muscles=[],
        secondary_muscles=[],
    )


class _Stub:
    def __init__(self, result: ExerciseTutorial | Exception | None) -> None:
        self.result = result
        self.calls = 0

    async def get_tutorial(self, _exercise_name: str) -> ExerciseTutorial | None:
        self.calls += 1
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


async def test_uses_the_primary_when_it_has_a_result() -> None:
    primary, fallback = _Stub(_tutorial("workoutx")), _Stub(_tutorial("free_exercise_db"))

    tutorial = await FallbackTutorialProvider(primary, fallback).get_tutorial("Bench Press")

    assert tutorial is not None
    assert tutorial.source == "workoutx"
    assert fallback.calls == 0


async def test_falls_back_when_the_primary_raises() -> None:
    primary, fallback = _Stub(RuntimeError("401")), _Stub(_tutorial("free_exercise_db"))

    tutorial = await FallbackTutorialProvider(primary, fallback).get_tutorial("Bench Press")

    assert tutorial is not None
    assert tutorial.source == "free_exercise_db"


async def test_falls_back_when_the_primary_has_no_match() -> None:
    primary, fallback = _Stub(None), _Stub(_tutorial("free_exercise_db"))

    tutorial = await FallbackTutorialProvider(primary, fallback).get_tutorial("Bench Press")

    assert tutorial is not None
    assert tutorial.source == "free_exercise_db"


async def test_returns_none_when_neither_has_a_match() -> None:
    provider = FallbackTutorialProvider(_Stub(None), _Stub(None))

    assert await provider.get_tutorial("Nope") is None


async def test_a_primary_failure_is_not_cached_so_a_fixed_key_takes_effect() -> None:
    primary = _Stub(RuntimeError("401"))
    provider = FallbackTutorialProvider(
        CachingTutorialProvider(primary), _Stub(_tutorial("free_exercise_db"))
    )

    first = await provider.get_tutorial("Bench Press")
    primary.result = _tutorial("workoutx")
    second = await provider.get_tutorial("Bench Press")

    assert first is not None and first.source == "free_exercise_db"
    assert second is not None and second.source == "workoutx"
    assert primary.calls == 2


async def test_a_primary_success_is_cached() -> None:
    primary = _Stub(_tutorial("workoutx"))
    provider = FallbackTutorialProvider(CachingTutorialProvider(primary), _Stub(None))

    await provider.get_tutorial("Bench Press")
    await provider.get_tutorial("Bench Press")

    assert primary.calls == 1
