from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.user import User
from dinatos_backend.schemas.planned_workout import CalendarFeedRead
from dinatos_backend.services.calendar import (
    build_ics,
    feed_planned_workouts,
    get_profile_by_calendar_token,
    new_calendar_token,
)
from dinatos_backend.services.profile import get_or_create_profile

router = APIRouter(tags=["calendar"])


def _feed(token: str | None) -> CalendarFeedRead:
    return CalendarFeedRead(
        token=token, path=f"/calendar/{token}.ics" if token is not None else None
    )


@router.get("/profile/calendar", response_model=CalendarFeedRead)
async def read_calendar_feed(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> CalendarFeedRead:
    """Whether the caller's calendar feed is on, and where it is."""
    return _feed((await get_or_create_profile(db, user.id)).calendar_token)


@router.post("/profile/calendar", response_model=CalendarFeedRead)
async def enable_calendar_feed(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> CalendarFeedRead:
    """Turns the feed on, or -- if it already is -- replaces its secret, which
    makes the old link stop working (for when it leaked, or to unsubscribe
    everyone who has it).
    """
    profile = await get_or_create_profile(db, user.id)
    profile.calendar_token = new_calendar_token()
    await db.commit()
    return _feed(profile.calendar_token)


@router.delete("/profile/calendar", status_code=status.HTTP_204_NO_CONTENT)
async def disable_calendar_feed(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> None:
    profile = await get_or_create_profile(db, user.id)
    profile.calendar_token = None
    await db.commit()


@router.get(
    "/calendar/{token}.ics",
    response_class=Response,
    responses={200: {"content": {"text/calendar": {}}}},
)
async def calendar_feed(token: str, db: AsyncSession = Depends(get_db)) -> Response:
    """The iCalendar feed itself. Unauthenticated by design -- calendar apps
    cannot log in -- so the unguessable `token` in the URL is the credential.
    """
    profile = await get_profile_by_calendar_token(db, token)
    if profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "calendar not found")
    workouts = await feed_planned_workouts(db, profile.id)
    return Response(
        build_ics(workouts),
        media_type="text/calendar; charset=utf-8",
        headers={"Cache-Control": "private, max-age=300"},
    )
