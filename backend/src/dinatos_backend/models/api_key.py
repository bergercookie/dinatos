from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class ApiKey(Base, TimestampMixin):
    """A long-lived credential a person creates for a tool (an MCP server, a
    script) to act as them, instead of handing it their password or a login
    session. Like `AuthSession`, only a SHA-256 of the secret is stored: the
    key itself is shown once, when it is created, and cannot be recovered.
    `suffix` -- the key's last few characters -- is kept in the clear purely
    so a person can tell their keys apart in a list.
    """

    __tablename__ = "api_keys"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(100))
    key_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    suffix: Mapped[str] = mapped_column(String(8))
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
