from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_current_session, get_current_user, get_session_user
from dinatos_backend.models.api_key import ApiKey
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.services.api_keys import hash_api_key
from dinatos_backend.services.auth import generate_session_token, hash_session_token


async def test_get_current_user_rejects_a_session_for_a_user_that_no_longer_exists(
    db: AsyncSession,
) -> None:
    """Deleting a user cascades to their sessions (see the `auth_sessions`
    migration's `ondelete="CASCADE"`), so this shouldn't be reachable
    through the API in practice -- this exercises the defensive check in
    `get_current_user` itself, against a session row that names a user id
    nothing backs.
    """
    token = generate_session_token()
    db.add(
        AuthSession(
            user_id=999999,
            token_hash=hash_session_token(token),
            expires_at=datetime.now(UTC) + timedelta(days=30),
        )
    )
    await db.commit()
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
    session = await get_current_session(credentials=credentials, db=db)

    with pytest.raises(HTTPException) as exc_info:
        await get_session_user(session=session, db=db)
    assert exc_info.value.status_code == 401
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(credentials=credentials, db=db)
    assert exc_info.value.status_code == 401


async def test_get_current_user_rejects_an_api_key_for_a_user_that_no_longer_exists(
    db: AsyncSession,
) -> None:
    key = "dnk_orphan"
    db.add(ApiKey(user_id=999999, name="orphan", key_hash=hash_api_key(key), suffix="ode"))
    await db.commit()
    credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=key)
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(credentials=credentials, db=db)
    assert exc_info.value.status_code == 401
