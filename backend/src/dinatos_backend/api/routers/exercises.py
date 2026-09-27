import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.schemas.exercise import (
    ExerciseCreate,
    ExerciseRead,
    ExerciseTutorialRead,
    ExerciseUpdate,
)
from dinatos_backend.services.tutorials import (
    ExerciseTutorial,
    TutorialProvider,
    get_tutorial_provider,
)

router = APIRouter(
    prefix="/exercises", tags=["exercises"], dependencies=[Depends(get_current_user)]
)

logger = logging.getLogger(__name__)


async def _get_or_404(db: AsyncSession, exercise_id: int) -> Exercise:
    exercise = await db.get(Exercise, exercise_id)
    if exercise is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "exercise not found")
    return exercise


@router.get("", response_model=list[ExerciseRead])
async def list_exercises(
    search: str | None = None, db: AsyncSession = Depends(get_db)
) -> list[Exercise]:
    """List exercises, optionally filtered by a case-insensitive name search --
    this backs the watch-sync picker's search box.
    """
    query = select(Exercise).order_by(Exercise.name)
    if search:
        query = query.where(Exercise.name.ilike(f"%{search}%"))
    result = await db.execute(query)
    return list(result.scalars())


@router.post("", response_model=ExerciseRead, status_code=status.HTTP_201_CREATED)
async def create_exercise(payload: ExerciseCreate, db: AsyncSession = Depends(get_db)) -> Exercise:
    exercise = Exercise(**payload.model_dump())
    db.add(exercise)
    await db.commit()
    await db.refresh(exercise)
    return exercise


@router.get("/{exercise_id}", response_model=ExerciseRead)
async def get_exercise(exercise_id: int, db: AsyncSession = Depends(get_db)) -> Exercise:
    return await _get_or_404(db, exercise_id)


@router.get("/{exercise_id}/tutorial", response_model=ExerciseTutorialRead)
async def get_exercise_tutorial(
    exercise_id: int,
    db: AsyncSession = Depends(get_db),
    provider: TutorialProvider = Depends(get_tutorial_provider),
) -> ExerciseTutorial:
    """A GIF plus instructions/muscles/equipment for this exercise, from
    whichever provider is active (see `services.tutorials`) -- looked up
    by name, since that's the only thing this catalog and either provider
    agree on.
    """
    exercise = await _get_or_404(db, exercise_id)
    try:
        tutorial = await provider.get_tutorial(exercise.name)
    except Exception as error:
        # Deliberately broad, not just `httpx.HTTPError`: a third-party
        # API's response shape is never fully trusted (a malformed body, an
        # unexpected missing field), and letting *any* of that surface as
        # an unhandled 500 has a real, non-obvious cost beyond a bad error
        # message -- FastAPI/Starlette's `ServerErrorMiddleware` sits
        # *outside* `CORSMiddleware` (add_middleware only wraps
        # `ExceptionMiddleware` inward), so a truly unhandled exception's
        # response never gets a CORS header at all. The browser then
        # reports a generic "CORS header missing" and hides the real
        # status/error entirely. Turning every failure here into an
        # `HTTPException` keeps it on the `ExceptionMiddleware` path
        # (inside CORS), where the response is a normal one CORSMiddleware
        # decorates like any other -- logged here since the client only
        # ever sees the generic message below, never this exception.
        logger.exception("tutorial provider fetch failed for exercise %d", exercise_id)
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "could not reach the tutorial provider"
        ) from error
    if tutorial is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no tutorial available for this exercise")
    return tutorial


@router.patch("/{exercise_id}", response_model=ExerciseRead)
async def update_exercise(
    exercise_id: int, payload: ExerciseUpdate, db: AsyncSession = Depends(get_db)
) -> Exercise:
    exercise = await _get_or_404(db, exercise_id)
    for field_name, value in payload.model_dump(exclude_unset=True).items():
        setattr(exercise, field_name, value)
    await db.commit()
    await db.refresh(exercise)
    return exercise


@router.delete("/{exercise_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_exercise(exercise_id: int, db: AsyncSession = Depends(get_db)) -> None:
    exercise = await _get_or_404(db, exercise_id)
    await db.delete(exercise)
    await db.commit()
