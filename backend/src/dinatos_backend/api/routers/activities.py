from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.activity import Activity, ActivityExercise, ActivitySet
from dinatos_backend.models.routine import Routine
from dinatos_backend.models.user import User
from dinatos_backend.schemas.activity import ActivityCreate, ActivityRead

router = APIRouter(prefix="/activities", tags=["activities"])

_WITH_EXERCISES_AND_SETS = selectinload(Activity.exercises).selectinload(ActivityExercise.sets)


def _build_exercises(payload: ActivityCreate) -> list[ActivityExercise]:
    return [
        ActivityExercise(
            exercise_id=item.exercise_id,
            superset_group=item.superset_group,
            notes=item.notes,
            position=position,
            sets=[
                ActivitySet(position=set_position, **set_item.model_dump())
                for set_position, set_item in enumerate(item.sets)
            ],
        )
        for position, item in enumerate(payload.exercises)
    ]


async def _get_or_404(db: AsyncSession, owner_id: int, activity_id: int) -> Activity:
    result = await db.execute(
        select(Activity)
        .options(_WITH_EXERCISES_AND_SETS)
        .where(Activity.id == activity_id, Activity.owner_id == owner_id)
    )
    activity = result.scalar_one_or_none()
    if activity is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "activity not found")
    return activity


async def _check_routine_ownership(db: AsyncSession, owner_id: int, routine_id: int | None) -> None:
    """An activity may reference a routine template -- but only one of the
    caller's own, never another user's by guessing its id.
    """
    if routine_id is None:
        return
    result = await db.execute(
        select(Routine.id).where(Routine.id == routine_id, Routine.owner_id == owner_id)
    )
    if result.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "routine not found")


@router.get("", response_model=list[ActivityRead])
async def list_activities(
    since: datetime | None = None,
    until: datetime | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[Activity]:
    query = (
        select(Activity)
        .options(_WITH_EXERCISES_AND_SETS)
        .where(Activity.owner_id == user.id)
        .order_by(Activity.started_at.desc())
    )
    if since is not None:
        query = query.where(Activity.started_at >= since)
    if until is not None:
        query = query.where(Activity.started_at <= until)
    result = await db.execute(query)
    return list(result.scalars())


@router.post("", response_model=ActivityRead, status_code=status.HTTP_201_CREATED)
async def create_activity(
    payload: ActivityCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Activity:
    await _check_routine_ownership(db, user.id, payload.routine_id)
    activity = Activity(
        owner_id=user.id,
        routine_id=payload.routine_id,
        title=payload.title,
        description=payload.description,
        started_at=payload.started_at,
        ended_at=payload.ended_at,
        exercises=_build_exercises(payload),
    )
    db.add(activity)
    await db.commit()
    return await _get_or_404(db, user.id, activity.id)


@router.get("/{activity_id}", response_model=ActivityRead)
async def get_activity(
    activity_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> Activity:
    return await _get_or_404(db, user.id, activity_id)


@router.put("/{activity_id}", response_model=ActivityRead)
async def replace_activity(
    activity_id: int,
    payload: ActivityCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Activity:
    """Replaces the activity in full, including its exercises and sets."""
    activity = await _get_or_404(db, user.id, activity_id)
    await _check_routine_ownership(db, user.id, payload.routine_id)
    activity.routine_id = payload.routine_id
    activity.title = payload.title
    activity.description = payload.description
    activity.started_at = payload.started_at
    activity.ended_at = payload.ended_at
    activity.exercises = _build_exercises(payload)
    await db.commit()
    return await _get_or_404(db, user.id, activity_id)


@router.delete("/{activity_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_activity(
    activity_id: int, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    activity = await _get_or_404(db, user.id, activity_id)
    await db.delete(activity)
    await db.commit()
