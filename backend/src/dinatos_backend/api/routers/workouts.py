from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.user import User
from dinatos_backend.models.workout import Workout, WorkoutExercise, WorkoutSet
from dinatos_backend.schemas.workout import WorkoutCreate, WorkoutRead

router = APIRouter(prefix="/workouts", tags=["workouts"])

_WITH_EXERCISES_AND_SETS = selectinload(Workout.exercises).selectinload(WorkoutExercise.sets)


def _build_exercises(payload: WorkoutCreate) -> list[WorkoutExercise]:
    return [
        WorkoutExercise(
            exercise_id=item.exercise_id,
            notes=item.notes,
            position=position,
            sets=[
                WorkoutSet(position=set_position, **set_item.model_dump())
                for set_position, set_item in enumerate(item.sets)
            ],
        )
        for position, item in enumerate(payload.exercises)
    ]


async def _get_or_404(db: AsyncSession, owner_id: int, workout_id: int) -> Workout:
    result = await db.execute(
        select(Workout)
        .options(_WITH_EXERCISES_AND_SETS)
        .where(Workout.id == workout_id, Workout.owner_id == owner_id)
    )
    workout = result.scalar_one_or_none()
    if workout is None:
        # Also the response for "exists, but belongs to someone else" --
        # never 403 here, which would confirm the id exists to a caller who
        # doesn't own it.
        raise HTTPException(status.HTTP_404_NOT_FOUND, "workout not found")
    return workout


@router.get("", response_model=list[WorkoutRead])
async def list_workouts(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[Workout]:
    result = await db.execute(
        select(Workout)
        .options(_WITH_EXERCISES_AND_SETS)
        .where(Workout.owner_id == user.id)
        .order_by(Workout.name)
    )
    return list(result.scalars())


@router.post("", response_model=WorkoutRead, status_code=status.HTTP_201_CREATED)
async def create_workout(
    payload: WorkoutCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Workout:
    workout = Workout(
        owner_id=user.id,
        name=payload.name,
        description=payload.description,
        exercises=_build_exercises(payload),
    )
    db.add(workout)
    await db.commit()
    return await _get_or_404(db, user.id, workout.id)


@router.get("/{workout_id}", response_model=WorkoutRead)
async def get_workout(
    workout_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> Workout:
    return await _get_or_404(db, user.id, workout_id)


@router.put("/{workout_id}", response_model=WorkoutRead)
async def replace_workout(
    workout_id: int,
    payload: WorkoutCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Workout:
    """Replaces the workout in full, including its exercises and sets --
    there is no separate endpoint for patching just one nested set.
    """
    workout = await _get_or_404(db, user.id, workout_id)
    workout.name = payload.name
    workout.description = payload.description
    workout.exercises = _build_exercises(payload)
    await db.commit()
    return await _get_or_404(db, user.id, workout_id)


@router.delete("/{workout_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_workout(
    workout_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    workout = await _get_or_404(db, user.id, workout_id)
    await db.delete(workout)
    await db.commit()
