from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class AuthSession(Base, TimestampMixin):
    """One row per login -- what makes a token revocable. `token_hash` is a
    SHA-256 digest, not the token itself: a high-entropy random token (see
    `services.auth.generate_session_token`) doesn't need Argon2's slowness
    the way a password does (nothing brute-forceable about it), but storing
    it in the clear would still hand out a valid session to anyone who reads
    this table. `revoked_at` set (by `POST /auth/logout`) or `expires_at`
    passed both make a session invalid; see `services.auth.get_valid_session`
    for where that's actually checked.
    """

    __tablename__ = "auth_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
