from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.db import get_db
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.models.user import User
from dinatos_backend.services.auth import get_valid_session

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


async def get_current_user(
    session: AuthSession = Depends(get_current_session),
    db: AsyncSession = Depends(get_db),
) -> User:
    user = await db.get(User, session.user_id)
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid or expired session")
    return user
