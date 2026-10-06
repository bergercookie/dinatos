"""API keys: creating, verifying, listing and revoking them.

A key is `dnk_` plus 32 random bytes, url-safe encoded. The prefix lets the
auth dependency tell a key from a login session's token without a lookup, and
lets secret scanners recognise one; the rest is as unguessable as a session
token, so (like `services.auth`) a plain SHA-256 of it is stored, never the
key itself.
"""

import hashlib
import secrets
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.api_key import ApiKey

KEY_PREFIX = "dnk_"
SUFFIX_LENGTH = 3
MAX_KEYS_PER_USER = 25

# `last_used_at` is for a person's eyes ("is this key still in use?"), not an
# audit log, so it is refreshed at most this often rather than on every call.
_LAST_USED_GRANULARITY = timedelta(minutes=1)


class TooManyApiKeysError(Exception):
    pass


def hash_api_key(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()


def looks_like_api_key(token: str) -> bool:
    return token.startswith(KEY_PREFIX)


async def create_api_key(db: AsyncSession, user_id: int, name: str) -> tuple[ApiKey, str]:
    """Returns the stored row and the plaintext key -- the one chance to see it."""
    count = await db.scalar(select(func.count()).where(ApiKey.user_id == user_id))
    if (count or 0) >= MAX_KEYS_PER_USER:
        raise TooManyApiKeysError
    key = KEY_PREFIX + secrets.token_urlsafe(32)
    row = ApiKey(
        user_id=user_id, name=name, key_hash=hash_api_key(key), suffix=key[-SUFFIX_LENGTH:]
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row, key


async def list_api_keys(db: AsyncSession, user_id: int) -> list[ApiKey]:
    result = await db.scalars(
        select(ApiKey).where(ApiKey.user_id == user_id).order_by(ApiKey.created_at, ApiKey.id)
    )
    return list(result)


async def delete_api_key(db: AsyncSession, user_id: int, key_id: int) -> bool:
    row = await db.scalar(select(ApiKey).where(ApiKey.id == key_id, ApiKey.user_id == user_id))
    if row is None:
        return False
    await db.delete(row)
    await db.commit()
    return True


async def get_api_key(db: AsyncSession, key: str) -> ApiKey | None:
    """The stored key for `key`, noting that it was just used."""
    row = await db.scalar(select(ApiKey).where(ApiKey.key_hash == hash_api_key(key)))
    if row is None:
        return None
    now = datetime.now(UTC)
    last = row.last_used_at
    if last is not None and last.tzinfo is None:
        last = last.replace(tzinfo=UTC)  # sqlite hands back naive timestamps
    if last is None or now - last > _LAST_USED_GRANULARITY:
        row.last_used_at = now
        await db.commit()
    return row
