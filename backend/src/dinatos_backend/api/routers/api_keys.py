"""Create, list and delete the caller's own API keys.

Managing keys needs a real login session: a key cannot mint, list or revoke
keys (so one that leaks cannot be used to dig in), and the key's plaintext is
returned exactly once, by the create call.
"""

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_session_user
from dinatos_backend.db import get_db
from dinatos_backend.models.user import User
from dinatos_backend.schemas.api_key import ApiKeyCreate, ApiKeyCreated, ApiKeyRead
from dinatos_backend.services.api_keys import (
    MAX_KEYS_PER_USER,
    TooManyApiKeysError,
    create_api_key,
    delete_api_key,
    list_api_keys,
)

router = APIRouter(prefix="/api-keys", tags=["api keys"])


@router.get("", response_model=list[ApiKeyRead])
async def list_keys(
    user: User = Depends(get_session_user), db: AsyncSession = Depends(get_db)
) -> list[ApiKeyRead]:
    return [ApiKeyRead.model_validate(row) for row in await list_api_keys(db, user.id)]


@router.post("", response_model=ApiKeyCreated, status_code=status.HTTP_201_CREATED)
async def create_key(
    payload: ApiKeyCreate,
    user: User = Depends(get_session_user),
    db: AsyncSession = Depends(get_db),
) -> ApiKeyCreated:
    """Creates a key. The response carries the key itself -- the only time it
    is ever shown; store it now.
    """
    try:
        row, key = await create_api_key(db, user.id, payload.name)
    except TooManyApiKeysError:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"at most {MAX_KEYS_PER_USER} API keys per account; delete one first",
        ) from None
    return ApiKeyCreated(**ApiKeyRead.model_validate(row).model_dump(), key=key)


@router.delete("/{key_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_key(
    key_id: int, user: User = Depends(get_session_user), db: AsyncSession = Depends(get_db)
) -> Response:
    if not await delete_api_key(db, user.id, key_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "API key not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)
