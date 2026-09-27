from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.config import Settings
from dinatos_backend.models.auth_session import AuthSession
from dinatos_backend.services.auth import (
    EmailAlreadyRegisteredError,
    InvalidCredentialsError,
    authenticate_user,
    bootstrap_admin_user,
    create_session,
    get_valid_session,
    hash_password,
    hash_session_token,
    register_user,
    revoke_session,
    verify_password,
)


def test_hash_password_is_salted_and_verifiable() -> None:
    hashed = hash_password("hunter22")
    assert hashed != "hunter22"
    assert verify_password("hunter22", hashed)
    assert not verify_password("wrong", hashed)
    # Argon2 salts every hash independently -- the same password twice
    # never produces the same stored value.
    assert hash_password("hunter22") != hashed


async def test_register_user_rejects_a_duplicate_email(db: AsyncSession) -> None:
    await register_user(db, "user@example.com", "hunter22")
    with pytest.raises(EmailAlreadyRegisteredError):
        await register_user(db, "user@example.com", "hunter22")


async def test_authenticate_user_rejects_wrong_password(db: AsyncSession) -> None:
    await register_user(db, "user@example.com", "hunter22")
    with pytest.raises(InvalidCredentialsError):
        await authenticate_user(db, "user@example.com", "wrong-password")


async def test_authenticate_user_rejects_unknown_email(db: AsyncSession) -> None:
    with pytest.raises(InvalidCredentialsError):
        await authenticate_user(db, "nobody@example.com", "hunter22")


async def test_create_session_then_get_valid_session_round_trips(db: AsyncSession) -> None:
    user = await register_user(db, "user@example.com", "hunter22")
    token = await create_session(db, user)

    session = await get_valid_session(db, token)

    assert session is not None
    assert session.user_id == user.id


async def test_get_valid_session_rejects_an_unknown_token(db: AsyncSession) -> None:
    assert await get_valid_session(db, "not-a-real-token") is None


async def test_get_valid_session_rejects_a_revoked_session(db: AsyncSession) -> None:
    user = await register_user(db, "user@example.com", "hunter22")
    token = await create_session(db, user)
    session = await get_valid_session(db, token)
    assert session is not None

    await revoke_session(db, session)

    assert await get_valid_session(db, token) is None


async def test_get_valid_session_rejects_an_expired_session(db: AsyncSession) -> None:
    user = await register_user(db, "user@example.com", "hunter22")
    token = "an-already-expired-token"
    db.add(
        AuthSession(
            user_id=user.id,
            token_hash=hash_session_token(token),
            expires_at=datetime.now(UTC) - timedelta(minutes=1),
        )
    )
    await db.commit()

    assert await get_valid_session(db, token) is None


async def test_bootstrap_admin_user_is_a_noop_without_both_settings(
    db: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    # Explicit, not just the ambient environment's `get_settings()`: a
    # `.env` in whatever directory this happens to run from (e.g. the
    # repo root's, for `just dev`) could otherwise leak a real
    # DINATOS_ADMIN_EMAIL/PASSWORD in and silently skip the "unset" case
    # this test means to cover.
    monkeypatch.setattr(
        "dinatos_backend.services.auth.get_settings",
        lambda: Settings(admin_email=None, admin_password=None),
    )

    await bootstrap_admin_user(db)

    with pytest.raises(InvalidCredentialsError):
        await authenticate_user(db, "admin@example.com", "hunter22")


async def test_bootstrap_admin_user_creates_the_configured_account_as_admin(
    db: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        "dinatos_backend.services.auth.get_settings",
        lambda: Settings(admin_email="admin@example.com", admin_password="hunter22"),
    )

    await bootstrap_admin_user(db)

    user = await authenticate_user(db, "admin@example.com", "hunter22")
    assert user.is_admin


async def test_bootstrap_admin_user_does_not_touch_an_already_existing_account(
    db: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A person who's since changed the bootstrapped account's password
    shouldn't have it silently reset back on every restart.
    """
    await register_user(db, "admin@example.com", "changed-password")
    monkeypatch.setattr(
        "dinatos_backend.services.auth.get_settings",
        lambda: Settings(admin_email="admin@example.com", admin_password="original-password"),
    )

    await bootstrap_admin_user(db)

    await authenticate_user(db, "admin@example.com", "changed-password")
    with pytest.raises(InvalidCredentialsError):
        await authenticate_user(db, "admin@example.com", "original-password")


async def test_revoking_one_session_does_not_affect_another(db: AsyncSession) -> None:
    """Two logins (two devices, or two browser tabs) each get their own
    session -- logging one out is not "log out everywhere."
    """
    user = await register_user(db, "user@example.com", "hunter22")
    token_a = await create_session(db, user)
    token_b = await create_session(db, user)

    session_a = await get_valid_session(db, token_a)
    assert session_a is not None
    await revoke_session(db, session_a)

    assert await get_valid_session(db, token_a) is None
    assert await get_valid_session(db, token_b) is not None
