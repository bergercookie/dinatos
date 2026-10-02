"""Account administration -- admin-only, regardless of whether
self-registration (`DINATOS_ALLOW_REGISTRATION`) is enabled.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import require_admin
from dinatos_backend.db import get_db
from dinatos_backend.models.user import User
from dinatos_backend.schemas.auth import AdminUserCreate, UserRead
from dinatos_backend.services.auth import EmailAlreadyRegisteredError, create_user

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin)])


@router.get("/users", response_model=list[UserRead])
async def list_users(db: AsyncSession = Depends(get_db)) -> list[User]:
    result = await db.execute(select(User).order_by(User.id))
    return list(result.scalars())


@router.post("/users", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def create_account(payload: AdminUserCreate, db: AsyncSession = Depends(get_db)) -> User:
    try:
        return await create_user(db, payload.email, payload.password, is_admin=payload.is_admin)
    except EmailAlreadyRegisteredError as error:
        raise HTTPException(status.HTTP_409_CONFLICT, "email already registered") from error
