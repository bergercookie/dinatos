import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from dinatos_backend.models.exercise import Equipment, Exercise, ExerciseMuscle, MuscleGroup
from dinatos_backend.models.user import User
from dinatos_backend.services.exercise import _default_exercises
from dinatos_backend.services.hevy_exercise_infer import (
    ExerciseInferrer,
    infer_equipment,
    split_equipment_suffix,
)
from dinatos_backend.services.hevy_import import import_hevy_workouts

_HEADER = (
    "title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,"
    "set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe\n"
)


def _catalog() -> list[Exercise]:
    return [Exercise(**fields) for fields in _default_exercises()]


def _csv(*titles: str) -> str:
    return _HEADER + "".join(
        f'Push,"1 Jan 2026, 08:00","1 Jan 2026, 09:00",,{title},,,0,normal,10,5,,,\n'
        for title in titles
    )


def test_split_equipment_suffix() -> None:
    assert split_equipment_suffix("Row (Dumbbell)") == ("Row", "dumbbell")
    assert split_equipment_suffix("Row") == ("Row", None)
    assert split_equipment_suffix("Fly (Cable) ") == ("Fly", "cable")


@pytest.mark.parametrize(
    ("title", "expected"),
    [
        ("Zottman Curl (Dumbbell)", Equipment.dumbbell),
        ("Zottman Curl (Barbell)", Equipment.barbell),
        ("Zottman Curl (Cable)", Equipment.cable),
        ("Zottman Curl (Machine)", Equipment.machine),
        ("Zottman Curl (Smith Machine)", Equipment.machine),
        ("Zottman Curl (Kettlebell)", Equipment.kettlebells),
        ("Zottman Curl (Bodyweight)", Equipment.body_only),
        ("Zottman Curl (Band)", Equipment.bands),
        ("Zottman Curl (Resistance Band)", Equipment.bands),
        ("Zottman Curl (EZ Bar)", Equipment.e_z_curl_bar),
        ("Zottman Curl (Medicine Ball)", Equipment.medicine_ball),
        ("Zottman Curl (Plate)", Equipment.other),
        ("ZOTTMAN CURL (DUMBBELL)", Equipment.dumbbell),
        # No suffix: equipment words in the name itself.
        ("Dumbbell Zottman Curl", Equipment.dumbbell),
        ("Zottman Barbell Curl", Equipment.barbell),
        ("EZ-Bar Zottman Curl", Equipment.e_z_curl_bar),
        ("Kettlebell Swing Variation", Equipment.kettlebells),
        ("Weird Pull Up", Equipment.body_only),
        # A recognised suffix wins over a conflicting word in the name.
        ("Dumbbell Thing (Cable)", Equipment.cable),
        # Unknown suffix: fall back to the name, else nothing.
        ("Dumbbell Thing (Banana)", Equipment.dumbbell),
        ("Zottman Curl (Banana)", None),
        ("Homemade Thing", None),
        ("", None),
    ],
)
def test_infer_equipment(title: str, expected: Equipment | None) -> None:
    assert infer_equipment(title) == expected


def test_neighbour_muscles_are_copied_from_similar_catalog_exercise() -> None:
    inferrer = ExerciseInferrer(_catalog())
    # Not an exact catalog name ("Bent Over Two-Dumbbell Row" is), so a custom
    # exercise would be created -- its muscles should follow the neighbour's.
    guess = inferrer.infer("Bent Over Row (Dumbbell)")
    assert guess.equipment == Equipment.dumbbell
    assert MuscleGroup.middle_back in guess.primary_muscles or (
        MuscleGroup.lats in guess.primary_muscles
    )
    assert guess.has_muscles


def test_neighbour_voting_uses_only_close_catalog_entries() -> None:
    inferrer = ExerciseInferrer(_catalog())
    neighbours = inferrer.similar("Lateral Raise (Cable)")
    assert neighbours
    scores = [score for score, _ in neighbours]
    assert scores == sorted(scores, reverse=True)
    assert all(score >= 0.6 for score in scores)
    assert len(neighbours) <= 3
    guess = inferrer.infer("Lateral Raise (Cable)")
    assert MuscleGroup.shoulders in guess.primary_muscles


def test_similarity_is_deterministic() -> None:
    first = ExerciseInferrer(_catalog()).infer("Incline Row (Dumbbell)")
    second = ExerciseInferrer(list(reversed(_catalog()))).infer("Incline Row (Dumbbell)")
    assert first == second


@pytest.mark.parametrize(
    ("title", "primary"),
    [
        ("Banana Curl", MuscleGroup.biceps),
        ("Wrist Curl Thing", MuscleGroup.forearms),
        ("Zzz Pulldown", MuscleGroup.lats),
        ("Zzz Calf Thing", MuscleGroup.calves),
        ("Zzz Shrug", MuscleGroup.traps),
    ],
)
def test_keyword_fallback_with_no_neighbours(title: str, primary: MuscleGroup) -> None:
    # An inferrer with an empty catalog can never find a neighbour.
    guess = ExerciseInferrer([]).infer(title)
    assert primary in guess.primary_muscles


def test_keyword_rules_are_ordered_specific_first() -> None:
    empty = ExerciseInferrer([])
    assert empty.infer("Zzz Leg Curl").primary_muscles == [MuscleGroup.hamstrings]
    assert empty.infer("Zzz Leg Press").primary_muscles == [MuscleGroup.quadriceps]
    assert empty.infer("Zzz Triceps Extension").primary_muscles == [MuscleGroup.triceps]
    assert MuscleGroup.chest in empty.infer("Zzz Bench Thing").primary_muscles
    # "reverse"/"rear" flies train the rear delts, not the chest.
    assert empty.infer("Zzz Reverse Fly").primary_muscles == [MuscleGroup.shoulders]
    assert empty.infer("Zzz Fly").primary_muscles == [MuscleGroup.chest]
    assert empty.infer("Zzz Overhead Press").primary_muscles == [MuscleGroup.shoulders]


@pytest.mark.parametrize("title", ["Homemade Thing", "Zorbing", "Spinning Kite (Banana)", ""])
def test_no_confident_guess_leaves_muscles_empty(title: str) -> None:
    guess = ExerciseInferrer(_catalog()).infer(title)
    assert guess.primary_muscles == []
    assert guess.secondary_muscles == []
    assert guess.has_muscles is False


def test_catalog_without_muscles_is_not_a_neighbour_source() -> None:
    bare = Exercise(name="Zottman Curl", is_custom=False)
    assert ExerciseInferrer([bare]).similar("Zottman Curl (Dumbbell)") == []


async def _seed(db: AsyncSession) -> int:
    db.add(User(email="m@example.com", password_hash="x"))
    db.add_all(_catalog())
    await db.commit()
    return (await db.execute(select(User.id))).scalar_one()


async def test_import_stores_and_reports_guesses(db: AsyncSession) -> None:
    owner_id = await _seed(db)

    result = await import_hevy_workouts(
        db, owner_id, _csv("Bench Press (Barbell)", "Zottman Curl (Dumbbell)", "Homemade Thing")
    )

    # The first is matched to the catalog, so only two are created.
    assert result.exercises_created == 2
    assert [e.name for e in result.created_exercises] == [
        "Zottman Curl (Dumbbell)",
        "Homemade Thing",
    ]
    curl, homemade = result.created_exercises
    assert curl.equipment == Equipment.dumbbell
    assert curl.equipment_guessed is True
    assert MuscleGroup.biceps in curl.primary_muscles
    assert curl.muscles_guessed is True
    assert homemade.equipment is None
    assert homemade.primary_muscles == []
    assert (homemade.equipment_guessed, homemade.muscles_guessed) == (False, False)

    stored = (
        await db.execute(
            select(Exercise)
            .where(Exercise.name == "Zottman Curl (Dumbbell)")
            .options(selectinload(Exercise.muscles))
        )
    ).scalar_one()
    assert stored.is_custom is True
    assert stored.equipment == Equipment.dumbbell
    assert stored.primary_muscles == curl.primary_muscles
    assert stored.secondary_muscles == curl.secondary_muscles


async def test_reimport_does_not_reinfer_or_report_existing_exercises(db: AsyncSession) -> None:
    owner_id = await _seed(db)
    csv_text = _csv("Zottman Curl (Dumbbell)")

    first = await import_hevy_workouts(db, owner_id, csv_text)
    second = await import_hevy_workouts(db, owner_id, csv_text)

    assert first.exercises_created == 1
    assert second.exercises_created == 0
    assert second.created_exercises == []
    rows = (
        await db.execute(select(Exercise).where(Exercise.name == "Zottman Curl (Dumbbell)"))
    ).all()
    assert len(rows) == 1


async def test_a_users_edits_to_a_guessed_exercise_survive_reimport(db: AsyncSession) -> None:
    owner_id = await _seed(db)
    csv_text = _csv("Zottman Curl (Dumbbell)")
    await import_hevy_workouts(db, owner_id, csv_text)

    exercise = (
        await db.execute(
            select(Exercise)
            .where(Exercise.name == "Zottman Curl (Dumbbell)")
            .options(selectinload(Exercise.muscles))
        )
    ).scalar_one()
    exercise.equipment = Equipment.cable
    exercise.muscles.clear()
    await db.commit()

    await import_hevy_workouts(db, owner_id, csv_text)
    await db.refresh(exercise, ["muscles"])
    assert exercise.equipment == Equipment.cable
    assert exercise.muscles == []


def _exercise(name: str, primary: list[MuscleGroup], secondary: list[MuscleGroup]) -> Exercise:
    return Exercise(
        name=name,
        is_custom=False,
        muscles=[
            *(ExerciseMuscle(muscle=m, is_primary=True) for m in primary),
            *(ExerciseMuscle(muscle=m, is_primary=False) for m in secondary),
        ],
    )


def test_vote_keeps_majority_muscles_and_drops_minority_ones() -> None:
    inferrer = ExerciseInferrer(
        [
            _exercise("Dumbbell Zonk Raise", [MuscleGroup.glutes], [MuscleGroup.calves]),
            _exercise("Barbell Zonk Raise", [MuscleGroup.glutes], [MuscleGroup.hamstrings]),
            _exercise("Cable Zonk Raise", [MuscleGroup.glutes], [MuscleGroup.calves]),
            _exercise("Smith Zonk Raise", [MuscleGroup.glutes, MuscleGroup.neck], []),
        ]
    )
    # Only the top three (ties broken by catalog name: Barbell, Cable, Dumbbell) vote.
    guess = inferrer.infer("Zonk Raise")
    assert guess.primary_muscles == [MuscleGroup.glutes]
    # calves 2/3 of the votes stay; hamstrings 1/3 is dropped; neck never voted.
    assert guess.secondary_muscles == [MuscleGroup.calves]
