from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.user import User
from dinatos_backend.schemas.imports import (
    IntervalsActivityList,
    IntervalsImportRequest,
    IntervalsImportResult,
    IntervalsSource,
)
from dinatos_backend.services.intervals_client import (
    IntervalsAuthError,
    IntervalsClient,
    IntervalsUnavailableError,
)
from dinatos_backend.services.intervals_import import (
    IntervalsImportConflictError,
    IntervalsSelectionError,
    build_preview,
    import_intervals_activities,
)

router = APIRouter(prefix="/imports/intervals", tags=["imports"])


async def get_intervals_client() -> IntervalsClient:
    return IntervalsClient()


async def _fetch(source: IntervalsSource, client: IntervalsClient) -> list[dict[str, object]]:
    try:
        return await client.list_activities(
            source.athlete_id, source.api_key, source.oldest, source.newest or date.today()
        )
    except IntervalsAuthError as error:
        # 400, not 401: a 401 from this API means *Dinatos's* bearer token is bad,
        # and clients react to that by logging the person out.
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(error)) from error
    except IntervalsUnavailableError as error:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(error)) from error


@router.post("/preview", response_model=IntervalsActivityList)
async def preview_activities(
    source: IntervalsSource,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    client: IntervalsClient = Depends(get_intervals_client),
) -> IntervalsActivityList:
    """List the person's Intervals.icu activities in a date window, so they can
    pick which to import. Writes nothing. Each entry says whether it was
    already imported, can't be imported, or starts alongside an activity
    Dinatos already has (likely the same workout, e.g. from Hevy).

    A POST because the API key travels in the body, not the URL; it is used
    for this request only and never stored.
    """
    return IntervalsActivityList(
        activities=await build_preview(db, user.id, await _fetch(source, client))
    )


@router.post("/activities", response_model=IntervalsImportResult)
async def import_activities(
    payload: IntervalsImportRequest,
    force: bool = False,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    client: IntervalsClient = Depends(get_intervals_client),
) -> IntervalsImportResult:
    """Import the chosen Intervals.icu activities (`activity_ids`, from the
    preview of the same window). All or nothing.

    An activity already imported before is rejected with 409, naming it and
    when -- the same rule as re-uploading an identical Hevy file -- unless
    `force=true`. Ids not in the window, or that can't be imported, are 422.
    """
    raw = await _fetch(payload, client)
    try:
        return await import_intervals_activities(
            db, user.id, raw, payload.activity_ids, force=force
        )
    except IntervalsSelectionError as error:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            {
                "message": (
                    "some selected activities were not found in this date range or "
                    "can't be imported"
                ),
                "not_found": error.missing,
                "unimportable": error.unimportable,
            },
        ) from error
    except IntervalsImportConflictError as error:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {
                "message": (
                    "some of these activities were already imported; pass "
                    "?force=true to import them again anyway"
                ),
                "already_imported": {k: v.isoformat() for k, v in error.already_imported.items()},
            },
        ) from error
