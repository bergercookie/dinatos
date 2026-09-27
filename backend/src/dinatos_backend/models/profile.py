import enum

from sqlalchemy import Enum, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class UnitSystem(enum.StrEnum):
    metric = "metric"
    imperial = "imperial"


class UserProfile(Base, TimestampMixin):
    """One row per user, keyed by that user's own id -- see
    `dinatos_backend.services.profile.get_or_create_profile`.
    """

    __tablename__ = "user_profile"

    id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    height_cm: Mapped[float | None]
    unit_system: Mapped[UnitSystem] = mapped_column(Enum(UnitSystem), default=UnitSystem.metric)
