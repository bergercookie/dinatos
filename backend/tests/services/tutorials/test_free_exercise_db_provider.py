from dinatos_backend.services.tutorials.free_exercise_db import (
    FreeExerciseDbProvider,
    load_free_exercise_db,
)


def test_load_free_exercise_db_has_no_duplicate_names() -> None:
    entries = load_free_exercise_db()
    names = [entry["name"] for entry in entries]
    assert len(names) == len(set(names))
    assert len(entries) > 800  # the vendored dataset is ~876 entries


async def test_get_tutorial_finds_an_exact_match() -> None:
    provider = FreeExerciseDbProvider()

    tutorial = await provider.get_tutorial("3/4 Sit-Up")

    assert tutorial is not None
    assert tutorial.source == "free_exercise_db"
    assert tutorial.gif_urls == [
        "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/3_4_Sit-Up/0.jpg",
        "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/3_4_Sit-Up/1.jpg",
    ]
    assert tutorial.instructions
    assert tutorial.primary_muscles == ["abdominals"]


async def test_get_tutorial_matches_case_insensitively() -> None:
    provider = FreeExerciseDbProvider()

    tutorial = await provider.get_tutorial("3/4 sit-up")

    assert tutorial is not None
    assert tutorial.primary_muscles == ["abdominals"]


async def test_get_tutorial_returns_none_for_an_unknown_name() -> None:
    provider = FreeExerciseDbProvider()

    assert await provider.get_tutorial("Not A Real Exercise") is None
