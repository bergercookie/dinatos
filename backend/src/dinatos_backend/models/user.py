from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class User(Base, TimestampMixin):
    """A local account. The first one ever created is promoted to admin --
    see `dinatos_backend.services.auth.register_user`.
    """

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    is_admin: Mapped[bool] = mapped_column(default=False)
