"""A handful of classic routines, seeded into each brand new account.

Routines are per-owner, so unlike the shared exercise catalog
(`services.exercise`) these are copied into every new account at creation
time rather than once per instance -- a person's first launch shows
something to start from instead of an empty list, and each copy is
theirs to edit or delete.

Exercises are looked up by name in the seeded catalog (names match the
vendored free-exercise-db dataset exactly). One that's missing -- the
catalog seeding is off, or the person's instance deleted it -- is skipped,
and a routine left with no exercises at all isn't created.
"""

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.config import get_settings
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.models.routine import Routine, RoutineExercise, RoutineSet
from dinatos_backend.models.user import User


@dataclass(frozen=True)
class _Move:
    exercise: str
    sets: int
    reps: int | None = None
    seconds: int | None = None


@dataclass(frozen=True)
class _Template:
    name: str
    description: str
    moves: tuple[_Move, ...]


_TEMPLATES = (
    _Template(
        "Push",
        "Chest, shoulders and triceps.",
        (
            _Move("Barbell Bench Press - Medium Grip", 4, 8),
            _Move("Standing Military Press", 3, 8),
            _Move("Barbell Incline Bench Press - Medium Grip", 3, 10),
            _Move("Side Lateral Raise", 3, 15),
            _Move("Triceps Pushdown", 3, 12),
        ),
    ),
    _Template(
        "Pull",
        "Back and biceps.",
        (
            _Move("Barbell Deadlift", 3, 5),
            _Move("Pullups", 3, 8),
            _Move("Bent Over Barbell Row", 4, 8),
            _Move("Face Pull", 3, 15),
            _Move("Barbell Curl", 3, 10),
        ),
    ),
    _Template(
        "Legs",
        "Quads, hamstrings, glutes and calves.",
        (
            _Move("Barbell Squat", 4, 6),
            _Move("Romanian Deadlift", 3, 8),
            _Move("Leg Press", 3, 12),
            _Move("Lying Leg Curls", 3, 12),
            _Move("Standing Calf Raises", 4, 15),
        ),
    ),
    _Template(
        "Upper body",
        "Chest, back, shoulders and arms in one session.",
        (
            _Move("Barbell Bench Press - Medium Grip", 4, 8),
            _Move("Bent Over Barbell Row", 4, 8),
            _Move("Dumbbell Shoulder Press", 3, 10),
            _Move("Wide-Grip Lat Pulldown", 3, 10),
            _Move("Dumbbell Bicep Curl", 3, 12),
            _Move("Triceps Pushdown", 3, 12),
        ),
    ),
    _Template(
        "Lower body",
        "Legs, glutes and core.",
        (
            _Move("Barbell Squat", 4, 8),
            _Move("Barbell Hip Thrust", 3, 10),
            _Move("Seated Leg Curl", 3, 12),
            _Move("Leg Extensions", 3, 12),
            _Move("Hanging Leg Raise", 3, 12),
        ),
    ),
    _Template(
        "Full body",
        "A balanced session for three days a week.",
        (
            _Move("Barbell Squat", 3, 5),
            _Move("Barbell Bench Press - Medium Grip", 3, 5),
            _Move("Bent Over Barbell Row", 3, 8),
            _Move("Standing Military Press", 3, 8),
            _Move("Romanian Deadlift", 2, 8),
            _Move("Plank", 3, seconds=45),
        ),
    ),
)


async def seed_starter_routines(db: AsyncSession, user: User) -> None:
    """Copies the starter routines into `user`'s account. Commits."""
    if not get_settings().seed_default_routines:
        return

    names = {move.exercise for template in _TEMPLATES for move in template.moves}
    found = await db.execute(select(Exercise).where(Exercise.name.in_(names)))
    by_name = {exercise.name: exercise for exercise in found.scalars()}

    for template in _TEMPLATES:
        moves = [move for move in template.moves if move.exercise in by_name]
        if not moves:
            continue
        db.add(
            Routine(
                owner_id=user.id,
                name=template.name,
                description=template.description,
                exercises=[
                    RoutineExercise(
                        exercise_id=by_name[move.exercise].id,
                        position=position,
                        sets=[
                            RoutineSet(
                                position=set_position,
                                target_reps=move.reps,
                                target_duration_seconds=move.seconds,
                            )
                            for set_position in range(move.sets)
                        ],
                    )
                    for position, move in enumerate(moves)
                ],
            )
        )
    await db.commit()
