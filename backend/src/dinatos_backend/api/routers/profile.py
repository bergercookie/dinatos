from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.profile import UserProfile
from dinatos_backend.models.user import User
from dinatos_backend.schemas.profile import ProfileRead, ProfileUpdate
from dinatos_backend.services.profile import get_or_create_profile

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
