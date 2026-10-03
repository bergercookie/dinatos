from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.routine import Routine, RoutineExercise, RoutineSet
from dinatos_backend.models.user import User
from dinatos_backend.schemas.routine import RoutineCreate, RoutineRead

router = APIRouter(prefix="/routines", tags=["routines"])

_WITH_EXERCISES_AND_SETS = selectinload(Routine.exercises).selectinload(RoutineExercise.sets)


def _build_exercises(payload: RoutineCreate) -> list[RoutineExercise]:
    return [
        RoutineExercise(
            exercise_id=item.exercise_id,
            superset_group=item.superset_group,
            notes=item.notes,
            position=position,
            sets=[
                RoutineSet(position=set_position, **set_item.model_dump())
                for set_position, set_item in enumerate(item.sets)
            ],
        )
        for position, item in enumerate(payload.exercises)
    ]


async def _get_or_404(db: AsyncSession, owner_id: int, routine_id: int) -> Routine:
    result = await db.execute(
        select(Routine)
        .options(_WITH_EXERCISES_AND_SETS)
        .where(Routine.id == routine_id, Routine.owner_id == owner_id)
    )
    routine = result.scalar_one_or_none()
    if routine is None:
        # Also the response for "exists, but belongs to someone else" --
        # never 403 here, which would confirm the id exists to a caller who
        # doesn't own it.
        raise HTTPException(status.HTTP_404_NOT_FOUND, "routine not found")
    return routine


@router.get("", response_model=list[RoutineRead])
async def list_routines(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> list[Routine]:
    result = await db.execute(
        select(Routine)
        .options(_WITH_EXERCISES_AND_SETS)
        .where(Routine.owner_id == user.id)
        .order_by(Routine.name)
    )
    return list(result.scalars())


@router.post("", response_model=RoutineRead, status_code=status.HTTP_201_CREATED)
async def create_routine(
    payload: RoutineCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Routine:
    routine = Routine(
        owner_id=user.id,
        name=payload.name,
        description=payload.description,
        exercises=_build_exercises(payload),
    )
    db.add(routine)
    await db.commit()
    return await _get_or_404(db, user.id, routine.id)


@router.get("/{routine_id}", response_model=RoutineRead)
async def get_routine(
    routine_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> Routine:
    return await _get_or_404(db, user.id, routine_id)


@router.put("/{routine_id}", response_model=RoutineRead)
async def replace_routine(
    routine_id: int,
    payload: RoutineCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Routine:
    """Replaces the routine in full, including its exercises and sets --
    there is no separate endpoint for patching just one nested set.
    """
    routine = await _get_or_404(db, user.id, routine_id)
    routine.name = payload.name
    routine.description = payload.description
    routine.exercises = _build_exercises(payload)
    await db.commit()
    return await _get_or_404(db, user.id, routine_id)


@router.delete("/{routine_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_routine(
    routine_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    routine = await _get_or_404(db, user.id, routine_id)
    await db.delete(routine)
    await db.commit()
