from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.planned_workout import PlannedWorkout
from dinatos_backend.models.routine import Routine
from dinatos_backend.models.user import User
from dinatos_backend.schemas.planned_workout import (
    PlannedWorkoutCreate,
    PlannedWorkoutRead,
    PlannedWorkoutUpdate,
)

router = APIRouter(prefix="/planned-workouts", tags=["planned-workouts"])


async def _get_or_404(db: AsyncSession, owner_id: int, planned_id: int) -> PlannedWorkout:
    result = await db.execute(
        select(PlannedWorkout).where(
            PlannedWorkout.id == planned_id, PlannedWorkout.owner_id == owner_id
        )
    )
    planned = result.scalar_one_or_none()
    if planned is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "planned workout not found")
    return planned


async def _routine_name(db: AsyncSession, owner_id: int, routine_id: int | None) -> str | None:
    """The name of one of the caller's own routines (404 for anyone else's,
    so an id can't be probed), or `None` when no routine is referenced.
    """
    if routine_id is None:
        return None
    name = await db.scalar(
        select(Routine.name).where(Routine.id == routine_id, Routine.owner_id == owner_id)
    )
    if name is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "routine not found")
    return name


async def _resolve_title(db: AsyncSession, owner_id: int, payload: PlannedWorkoutCreate) -> str:
    """The given title, else the name of the routine being planned."""
    routine_name = await _routine_name(db, owner_id, payload.routine_id)
    title = payload.title or routine_name
    if title is None:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "give a title, or pick a routine to plan"
        )
    return title


@router.get("", response_model=list[PlannedWorkoutRead])
async def list_planned_workouts(
    since: datetime | None = None,
    until: datetime | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[PlannedWorkout]:
    """The caller's planned workouts, soonest first, optionally bounded by time."""
    query = (
        select(PlannedWorkout)
        .where(PlannedWorkout.owner_id == user.id)
        .order_by(PlannedWorkout.scheduled_at, PlannedWorkout.id)
    )
    if since is not None:
        query = query.where(PlannedWorkout.scheduled_at >= since)
    if until is not None:
        query = query.where(PlannedWorkout.scheduled_at <= until)
    return list((await db.execute(query)).scalars())


@router.post("", response_model=PlannedWorkoutRead, status_code=status.HTTP_201_CREATED)
async def create_planned_workout(
    payload: PlannedWorkoutCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PlannedWorkout:
    title = await _resolve_title(db, user.id, payload)
    planned = PlannedWorkout(owner_id=user.id, **{**payload.model_dump(), "title": title})
    db.add(planned)
    await db.commit()
    await db.refresh(planned)
    return planned


@router.get("/{planned_id}", response_model=PlannedWorkoutRead)
async def get_planned_workout(
    planned_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> PlannedWorkout:
    return await _get_or_404(db, user.id, planned_id)


@router.put("/{planned_id}", response_model=PlannedWorkoutRead)
async def replace_planned_workout(
    planned_id: int,
    payload: PlannedWorkoutCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PlannedWorkout:
    planned = await _get_or_404(db, user.id, planned_id)
    title = await _resolve_title(db, user.id, payload)
    for field_name, value in {**payload.model_dump(), "title": title}.items():
        setattr(planned, field_name, value)
    await db.commit()
    await db.refresh(planned)
    return planned


@router.patch("/{planned_id}", response_model=PlannedWorkoutRead)
async def update_planned_workout(
    planned_id: int,
    payload: PlannedWorkoutUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PlannedWorkout:
    planned = await _get_or_404(db, user.id, planned_id)
    changes = payload.model_dump(exclude_unset=True)
    await _routine_name(db, user.id, changes.get("routine_id"))
    # Required columns: sending null for one means "leave it", not "clear it".
    for required in ("title", "scheduled_at", "duration_minutes"):
        if changes.get(required, "") is None:
            del changes[required]
    for field_name, value in changes.items():
        setattr(planned, field_name, value)
    await db.commit()
    await db.refresh(planned)
    return planned


@router.delete("/{planned_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_planned_workout(
    planned_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    planned = await _get_or_404(db, user.id, planned_id)
    await db.delete(planned)
    await db.commit()
