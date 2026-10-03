import logging

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from dinatos_backend.api.deps import (
    get_current_user,
    get_tutorial_provider_for_user,
    get_workoutx_provider_for_user,
)
from dinatos_backend.db import get_db
from dinatos_backend.models.activity import Activity, ActivityExercise, ActivitySet
from dinatos_backend.models.exercise import Equipment, Exercise, ExerciseMuscle, MuscleGroup
from dinatos_backend.models.user import User
from dinatos_backend.schemas.exercise import (
    ExerciseCreate,
    ExerciseRead,
    ExerciseRecordsRead,
    ExerciseTutorialRead,
    ExerciseUpdate,
)
from dinatos_backend.services.tutorials import ExerciseTutorial, TutorialProvider
from dinatos_backend.services.tutorials.workoutx import GIF_ID_RE, WorkoutXProvider

router = APIRouter(
    prefix="/exercises", tags=["exercises"], dependencies=[Depends(get_current_user)]
)

logger = logging.getLogger(__name__)

# `muscles` is a relationship, not a plain column -- without eager-loading it
# up front, the response model's `primary_muscles`/`secondary_muscles`
# properties (which read it) would trigger an implicit lazy load while
# FastAPI serializes the response, outside of any `await`, which raises
# `MissingGreenlet` under the async engine rather than silently working the
# way a sync session would.
_WITH_MUSCLES = selectinload(Exercise.muscles)


async def _get_or_404(db: AsyncSession, exercise_id: int) -> Exercise:
    exercise = await db.get(Exercise, exercise_id, options=[_WITH_MUSCLES])
    if exercise is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "exercise not found")
    return exercise


async def _refresh_with_muscles(db: AsyncSession, exercise: Exercise) -> None:
    await db.refresh(exercise)
    await db.refresh(exercise, attribute_names=["muscles"])


def _ensure_custom(exercise: Exercise) -> None:
    """Guards the two mutations (`update`/`delete`) the shipped, seeded
    catalog must never allow -- see `Exercise.is_custom`'s docstring for why.
    """
    if not exercise.is_custom:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "built-in exercises cannot be edited or deleted"
        )


def _muscle_rows(
    primary_muscles: list[MuscleGroup], secondary_muscles: list[MuscleGroup]
) -> list[ExerciseMuscle]:
    """Primary wins when the same muscle is listed as both -- `ExerciseMuscle`
    only allows one row per (exercise, muscle) (see its unique constraint),
    and a muscle someone marked primary shouldn't be demoted by also
    appearing in their secondary list.
    """
    primary_muscles = list(dict.fromkeys(primary_muscles))
    secondary_muscles = list(dict.fromkeys(secondary_muscles))
    secondary_muscles = [muscle for muscle in secondary_muscles if muscle not in primary_muscles]
    return [ExerciseMuscle(muscle=muscle, is_primary=True) for muscle in primary_muscles] + [
        ExerciseMuscle(muscle=muscle, is_primary=False) for muscle in secondary_muscles
    ]


@router.get("", response_model=list[ExerciseRead])
async def list_exercises(
    response: Response,
    search: str | None = None,
    muscle: MuscleGroup | None = None,
    equipment: Equipment | None = None,
    limit: int | None = Query(None, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
) -> list[Exercise]:
    """List exercises, optionally filtered by a case-insensitive name search --
    this backs the watch-sync picker's search box, and the exercises list
    screen, and the routine/activity exercise pickers.

    `muscle`/`equipment` back the "which exercises train this muscle" /
    "which exercises use this equipment" lookups the frontend offers from
    an exercise's own muscle/equipment chips -- `muscle` matches either a
    primary or secondary muscle, since both count as "trains this muscle".

    `limit`/`offset` are opt-in: the pickers omit them and get every matching
    row in one shot, exactly as before pagination existed, since they need
    the full set to build their own in-memory picker/lookup. The exercises
    list screen passes them to page through the catalog instead of fetching
    everything up front. Either way the true total (before slicing) comes
    back via the `X-Total-Count` header rather than an envelope, so the
    response body's shape -- a bare array -- never changes for callers that
    don't ask for a page.
    """
    query = select(Exercise).order_by(Exercise.name).options(_WITH_MUSCLES)
    if search:
        query = query.where(Exercise.name.ilike(f"%{search}%"))
    if muscle is not None:
        query = query.where(Exercise.muscles.any(ExerciseMuscle.muscle == muscle))
    if equipment is not None:
        query = query.where(Exercise.equipment == equipment)
    total = await db.scalar(select(func.count()).select_from(query.subquery()))
    response.headers["X-Total-Count"] = str(total or 0)
    if limit is not None:
        query = query.limit(limit).offset(offset)
    result = await db.execute(query)
    return list(result.scalars())


@router.post("", response_model=ExerciseRead, status_code=status.HTTP_201_CREATED)
async def create_exercise(payload: ExerciseCreate, db: AsyncSession = Depends(get_db)) -> Exercise:
    data = payload.model_dump()
    primary_muscles = data.pop("primary_muscles")
    secondary_muscles = data.pop("secondary_muscles")
    # is_custom is never accepted from the client (see ExerciseCreate) --
    # anything created through this endpoint is by definition someone's own
    # exercise, never part of the shipped catalog.
    exercise = Exercise(
        **data, is_custom=True, muscles=_muscle_rows(primary_muscles, secondary_muscles)
    )
    db.add(exercise)
    await db.commit()
    await _refresh_with_muscles(db, exercise)
    return exercise


@router.get("/{exercise_id}", response_model=ExerciseRead)
async def get_exercise(exercise_id: int, db: AsyncSession = Depends(get_db)) -> Exercise:
    return await _get_or_404(db, exercise_id)


@router.get("/{exercise_id}/tutorial", response_model=ExerciseTutorialRead)
async def get_exercise_tutorial(
    exercise_id: int,
    db: AsyncSession = Depends(get_db),
    provider: TutorialProvider = Depends(get_tutorial_provider_for_user),
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
        # Deliberately broad, not just `httpx2.HTTPError`: a third-party
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


@router.get("/media/workoutx/{gif_id}.gif")
async def get_workoutx_gif(
    gif_id: str, provider: WorkoutXProvider = Depends(get_workoutx_provider_for_user)
) -> Response:
    """A WorkoutX GIF, proxied with the caller's own API key. WorkoutX's
    media URLs answer 401 without the key (header or query param), and an
    `<img>`/`Image.network` can't send a header -- while putting the key in
    the URL would leak it to the client and any log along the way -- so the
    key stays server-side and the app fetches the bytes from here instead.
    """
    if not GIF_ID_RE.fullmatch(gif_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "gif not found")
    try:
        content, content_type = await provider.get_gif(gif_id)
    except Exception as error:
        logger.exception("WorkoutX gif fetch failed for %r", gif_id)
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "could not reach the tutorial provider"
        ) from error
    return Response(
        content, media_type=content_type, headers={"Cache-Control": "private, max-age=86400"}
    )


@router.get("/{exercise_id}/records", response_model=ExerciseRecordsRead)
async def get_exercise_records(
    exercise_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ExerciseRecordsRead:
    """The caller's own all-time best weight and best reps for this exercise,
    across every past `ActivitySet` logged against it (any past activity,
    not just one) -- what a live-recording session's end-of-workout summary
    compares its own best set against to flag a new personal record. Scoped
    to `user.id` the same way `activities.list_activities` is, so one
    account's bests never leak into another's.
    """
    await _get_or_404(db, exercise_id)
    result = await db.execute(
        select(func.max(ActivitySet.weight_kg), func.max(ActivitySet.reps))
        .select_from(ActivitySet)
        .join(ActivityExercise, ActivitySet.activity_exercise_id == ActivityExercise.id)
        .join(Activity, ActivityExercise.activity_id == Activity.id)
        .where(Activity.owner_id == user.id, ActivityExercise.exercise_id == exercise_id)
    )
    max_weight_kg, max_reps = result.one()
    return ExerciseRecordsRead(max_weight_kg=max_weight_kg, max_reps=max_reps)


@router.patch("/{exercise_id}", response_model=ExerciseRead)
async def update_exercise(
    exercise_id: int, payload: ExerciseUpdate, db: AsyncSession = Depends(get_db)
) -> Exercise:
    exercise = await _get_or_404(db, exercise_id)
    _ensure_custom(exercise)
    data = payload.model_dump(exclude_unset=True)
    # Popped out rather than `setattr` like every other field: `muscles` is
    # a relationship, not a plain column, so it's replaced wholesale below
    # instead -- but only when at least one of the two lists was actually
    # given, so an update that doesn't mention muscles at all leaves them
    # untouched.
    primary_muscles = data.pop("primary_muscles", None)
    secondary_muscles = data.pop("secondary_muscles", None)
    for field_name, value in data.items():
        setattr(exercise, field_name, value)
    if primary_muscles is not None or secondary_muscles is not None:
        rows = _muscle_rows(
            primary_muscles if primary_muscles is not None else exercise.primary_muscles,
            secondary_muscles if secondary_muscles is not None else exercise.secondary_muscles,
        )
        # Not just `exercise.muscles = rows`: when a muscle carries over
        # unchanged, the new row and the old row it's replacing share the
        # same (exercise, muscle) unique constraint, and the unit of work
        # can flush the insert before the delete it's paired with -- an
        # explicit delete, flushed first, avoids that ordering trip.
        await db.execute(delete(ExerciseMuscle).where(ExerciseMuscle.exercise_id == exercise.id))
        await db.flush()
        exercise.muscles = rows
    await db.commit()
    await _refresh_with_muscles(db, exercise)
    return exercise


@router.delete("/{exercise_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_exercise(exercise_id: int, db: AsyncSession = Depends(get_db)) -> None:
    exercise = await _get_or_404(db, exercise_id)
    _ensure_custom(exercise)
    await db.delete(exercise)
    await db.commit()
