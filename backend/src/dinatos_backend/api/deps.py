from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.db import get_db
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.models.user import User
from dinatos_backend.services.api_keys import get_api_key, looks_like_api_key
from dinatos_backend.services.auth import get_valid_session
from dinatos_backend.services.profile import get_or_create_profile
from dinatos_backend.services.tutorials import (
    TutorialProvider,
    get_tutorial_provider_for_key,
    get_workoutx_provider,
)
from dinatos_backend.services.tutorials.workoutx import WorkoutXProvider

_bearer_scheme = HTTPBearer()


async def get_current_session(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> AuthSession:
    """The session named by the caller's bearer token -- separate from
    `get_current_user` so `POST /auth/logout` can depend on it directly and
    revoke exactly this session, not just "whoever the token belongs to".
    """
    session = await get_valid_session(db, credentials.credentials)
    if session is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired session")
    return session


async def get_session_user(
    session: AuthSession = Depends(get_current_session),
    db: AsyncSession = Depends(get_db),
) -> User:
    """The user behind a login session -- an API key is not accepted. For
    what a key must never do: manage keys, administer the server.
    """
    user = await db.get(User, session.user_id)
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired session")
    return user


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    """The caller, from either credential: an API key (`dnk_...`) or a login
    session's token.
    """
    token = credentials.credentials
    if looks_like_api_key(token):
        key = await get_api_key(db, token)
        user = await db.get(User, key.user_id) if key is not None else None
        if user is None:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid API key")
        return user
    session = await get_valid_session(db, token)
    user = await db.get(User, session.user_id) if session is not None else None
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired session")
    return user


async def require_admin(user: User = Depends(get_session_user)) -> User:
    if not user.is_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "admin access required")
    return user


async def get_tutorial_provider_for_user(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> TutorialProvider:
    """Tutorials for this caller: via their own saved WorkoutX key if they
    have one, else the instance-wide provider.
    """
    profile = await get_or_create_profile(db, user.id)
    return get_tutorial_provider_for_key(profile.workoutx_api_key)


async def get_workoutx_provider_for_user(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
) -> WorkoutXProvider:
    """The caller's own WorkoutX adapter (for fetching GIFs, which need
    their key); 404 if they haven't saved one.
    """
    profile = await get_or_create_profile(db, user.id)
    if not profile.workoutx_api_key:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no WorkoutX API key saved")
    return get_workoutx_provider(profile.workoutx_api_key)
