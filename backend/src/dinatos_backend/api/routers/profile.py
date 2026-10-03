from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.profile import UserProfile
from dinatos_backend.models.user import User
from dinatos_backend.schemas.backup import UserExport, UserImportMode, UserImportResult
from dinatos_backend.schemas.profile import ProfileRead, ProfileUpdate
from dinatos_backend.services.profile import get_or_create_profile
from dinatos_backend.services.user_export import (
    UserImportInvalidError,
    export_user_data,
    import_user_data,
)

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("", response_model=ProfileRead)
async def read_profile(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> UserProfile:
    return await get_or_create_profile(db, user.id)


@router.patch("", response_model=ProfileRead)
async def update_profile(
    payload: ProfileUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserProfile:
    profile = await get_or_create_profile(db, user.id)
    for field_name, value in payload.model_dump(exclude_unset=True).items():
        setattr(profile, field_name, value)
    await db.commit()
    await db.refresh(profile)
    return profile


@router.get("/export", response_model=UserExport)
async def export_my_data(
    request: Request,
    response: Response,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserExport:
    """The caller's own settings, routines, activities and measurements (plus
    the exercises they use) as a JSON file. No password hash, no API key.
    """
    stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    response.headers["Content-Disposition"] = f'attachment; filename="dinatos-export-{stamp}.json"'
    return await export_user_data(db, user, request.app.version)


@router.post("/import", response_model=UserImportResult)
async def import_my_data(
    payload: UserExport,
    mode: UserImportMode = UserImportMode.merge,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UserImportResult:
    """Load a file from `GET /profile/export` into the caller's own account.
    `mode=merge` (default) keeps everything already there and skips what is
    already present (same routine name, same activity title and start, same
    measurement time), so re-importing a file is harmless. `mode=replace`
    deletes the caller's routines, activities and measurements first.
    """
    try:
        return await import_user_data(db, user, payload, mode)
    except UserImportInvalidError as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(error)) from error
