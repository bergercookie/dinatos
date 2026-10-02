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
from dinatos_backend.schemas.auth import (
    AuthConfig,
    LoginRequest,
    TokenResponse,
    UserCreate,
    UserRead,
)
from dinatos_backend.services.auth import (
    EmailAlreadyRegisteredError,
    InvalidCredentialsError,
    authenticate_user,
    create_session,
    is_registration_open,
    register_user,
    revoke_session,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/config", response_model=AuthConfig)
async def read_auth_config(db: AsyncSession = Depends(get_db)) -> AuthConfig:
    """Public: lets the login screen hide its "Register" link when
    self-registration is turned off (`DINATOS_ALLOW_REGISTRATION`).
    """
    return AuthConfig(registration_enabled=await is_registration_open(db))


@router.post("/register", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def register(payload: UserCreate, db: AsyncSession = Depends(get_db)) -> User:
    """The first account ever created on an instance is its admin. Rejected
    with 403 once self-registration is disabled (an admin creates accounts
    via `POST /admin/users` then).
    """
    if not await is_registration_open(db):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "registration is disabled")
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
