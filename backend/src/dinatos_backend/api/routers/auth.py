"""Registration, login, logout, and "who am I".

Authentication is a server-side session per login (see `services/auth.py`),
so logout is real: it revokes exactly the session the caller's bearer token
names, and every subsequent request with that same token gets a 401 --
other sessions the same account has open elsewhere (another device, another
browser tab that logged in separately) are unaffected.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_session, get_current_user
from dinatos_backend.db import get_db
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.models.user import User
from dinatos_backend.schemas.auth import LoginRequest, TokenResponse, UserCreate, UserRead
from dinatos_backend.services.auth import (
    EmailAlreadyRegisteredError,
    InvalidCredentialsError,
    authenticate_user,
    create_session,
    register_user,
    revoke_session,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def register(payload: UserCreate, db: AsyncSession = Depends(get_db)) -> User:
    """The first account ever created on an instance is its admin."""
    try:
        return await register_user(db, payload.email, payload.password)
    except EmailAlreadyRegisteredError as error:
        raise HTTPException(status.HTTP_409_CONFLICT, "email already registered") from error


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)) -> TokenResponse:
    try:
        user = await authenticate_user(db, payload.email, payload.password)
    except InvalidCredentialsError as error:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid email or password") from error
    return TokenResponse(access_token=await create_session(db, user))


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    session: AuthSession = Depends(get_current_session), db: AsyncSession = Depends(get_db)
) -> None:
    await revoke_session(db, session)


@router.get("/me", response_model=UserRead)
async def read_current_user(user: User = Depends(get_current_user)) -> User:
    return user
