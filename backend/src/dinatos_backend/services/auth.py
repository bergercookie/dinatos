"""Password hashing, and session issuing/verification/revocation.

Authentication is a server-side session per login (`AuthSession`), not a
self-verifying token: the string handed to the client is nothing but a
high-entropy random value, meaningless without the database row it happens
to be a key into. See `docs/architecture/backend.md`'s "Authentication" section for
why this replaced the earlier stateless-JWT design -- a signed,
self-verifying token buys nothing once every request already needs a
database lookup anyway, and giving that up is what makes `POST /auth/logout`
real: it revokes exactly the session that called it, nothing else.
"""

import hashlib
import secrets
from datetime import UTC, datetime, timedelta

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.config import get_settings
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.models.user import User
from dinatos_backend.services.starter_routines import seed_starter_routines

_hasher = PasswordHasher()


class EmailAlreadyRegisteredError(Exception):
    pass


class InvalidCredentialsError(Exception):
    """Wrong email/password at login."""


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        _hasher.verify(password_hash, password)
    except VerifyMismatchError:
        return False
    return True


async def _has_any_user(db: AsyncSession) -> bool:
    return (await db.execute(select(User).limit(1))).scalar_one_or_none() is not None


async def is_registration_open(db: AsyncSession) -> bool:
    """Whether `POST /auth/register` should currently be accepted: the
    `allow_registration` setting, except that an instance with no accounts
    yet is always open -- nobody could create the first (admin) one
    otherwise, short of `admin_email`/`admin_password` being configured.
    """
    return get_settings().allow_registration or not await _has_any_user(db)


async def create_user(
    db: AsyncSession, email: str, password: str, *, is_admin: bool | None = None
) -> User:
    """Creates an account. `is_admin=None` means "the default": the very
    first account on a fresh instance has no one to grant it admin, so it
    grants itself, and every account after that starts plain.
    """
    existing = await db.execute(select(User).where(User.email == email))
    if existing.scalar_one_or_none() is not None:
        raise EmailAlreadyRegisteredError

    if is_admin is None:
        is_admin = not await _has_any_user(db)

    user = User(email=email, password_hash=hash_password(password), is_admin=is_admin)
    db.add(user)
    await db.commit()
    await db.refresh(user)
    await seed_starter_routines(db, user)
    return user


async def register_user(db: AsyncSession, email: str, password: str) -> User:
    return await create_user(db, email, password)


async def bootstrap_admin_user(db: AsyncSession) -> None:
    """Creates `settings.admin_email`/`admin_password` as an admin account
    if it doesn't already exist -- a no-op if either setting is unset (the
    common case for an already-running instance), and a no-op if the
    account already exists (never touches its password: a person who's
    since changed it shouldn't have it silently reset back on every
    restart). This is what lets a fresh instance's first login work
    without a manual `POST /auth/register` first; called once from the
    app's lifespan startup, after migrations have run.

    Explicitly `is_admin=True` here, unlike `register_user`'s "first
    account becomes admin" rule -- this account should end up admin
    whether or not anyone else has already registered.
    """
    settings = get_settings()
    # Not `is None`: docker-compose.yml passes these through as `${VAR:-}`,
    # which is an empty string, not an absent one, when unset in `.env`.
    if not settings.admin_email or not settings.admin_password:
        return

    existing = await db.execute(select(User).where(User.email == settings.admin_email))
    if existing.scalar_one_or_none() is not None:
        return

    admin = User(
        email=settings.admin_email,
        password_hash=hash_password(settings.admin_password),
        is_admin=True,
    )
    db.add(admin)
    await db.commit()
    await seed_starter_routines(db, admin)


async def authenticate_user(db: AsyncSession, email: str, password: str) -> User:
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()
    if user is None or not verify_password(password, user.password_hash):
        raise InvalidCredentialsError
    return user


def generate_session_token() -> str:
    """32 bytes of randomness, url-safe-encoded -- unguessable regardless of
    how the resulting hash is stored (see `hash_session_token`).
    """
    return secrets.token_urlsafe(32)


def hash_session_token(token: str) -> str:
    """SHA-256, not Argon2: this hashes a high-entropy random token, not a
    human password -- there's nothing brute-forceable to defend against, so
    Argon2's deliberate slowness would only cost real request latency for no
    security benefit. Same reasoning as `hevy_import.hash_csv_content`;
    never use this for a password.
    """
    return hashlib.sha256(token.encode()).hexdigest()


async def create_session(db: AsyncSession, user: User) -> str:
    """Log `user` in: create a new session row and return the raw token --
    the only moment it exists outside the client, since only its hash is
    ever stored.
    """
    token = generate_session_token()
    settings = get_settings()
    session = AuthSession(
        user_id=user.id,
        token_hash=hash_session_token(token),
        expires_at=datetime.now(UTC) + timedelta(days=settings.session_ttl_days),
    )
    db.add(session)
    await db.commit()
    return token


async def get_valid_session(db: AsyncSession, token: str) -> AuthSession | None:
    """The token from an `Authorization: Bearer <token>` header -> the
    session it names, or `None` if it doesn't name one that's still good
    (never existed, already revoked, or past its `expires_at`). The
    expiry check runs as SQL (`func.now()`), not a Python-side
    `datetime.now()` comparison, to sidestep any timezone-awareness
    mismatch between what a driver hands back and what Python considers
    "now" -- the same reason `TimestampMixin` uses `server_default=func.now()`
    rather than setting timestamps from application code.
    """
    result = await db.execute(
        select(AuthSession).where(
            AuthSession.token_hash == hash_session_token(token),
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > func.now(),
        )
    )
    return result.scalar_one_or_none()


async def revoke_session(db: AsyncSession, session: AuthSession) -> None:
    """Log out: revoke exactly this one session, not every session the
    account has open elsewhere (see `docs/architecture/backend.md`'s
    "Authentication").
    """
    session.revoked_at = datetime.now(UTC)
    await db.commit()
