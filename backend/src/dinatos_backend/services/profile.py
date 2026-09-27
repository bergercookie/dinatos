from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.profile import UserProfile


async def get_or_create_profile(db: AsyncSession, user_id: int) -> UserProfile:
    profile = await db.get(UserProfile, user_id)
    if profile is None:
        profile = UserProfile(id=user_id)
        db.add(profile)
        await db.commit()
        await db.refresh(profile)
    return profile
