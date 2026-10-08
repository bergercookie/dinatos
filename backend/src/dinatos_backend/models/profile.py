import enum

from sqlalchemy import Enum, ForeignKey, String
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
    # This user's own WorkoutX (https://workoutxapp.com) API key, used for
    # *their* exercise tutorials instead of the bundled dataset -- see
    # `services.tutorials.get_tutorial_provider_for_user`. Stored as-is
    # (it has to be sent to WorkoutX on every lookup, so a one-way hash
    # would be useless) and never returned by the API: `ProfileRead` only
    # exposes whether one is set.
    workoutx_api_key: Mapped[str | None] = mapped_column(String(255))
    # The secret in this user's calendar-feed URL (`GET /calendar/{token}.ics`),
    # which calendar apps fetch without being able to log in. Stored as-is
    # (unlike an API key it is shown again, so the person can re-copy the
    # link) and never part of the per-user export. `None` = feed disabled.
    calendar_token: Mapped[str | None] = mapped_column(String(64), unique=True, index=True)
