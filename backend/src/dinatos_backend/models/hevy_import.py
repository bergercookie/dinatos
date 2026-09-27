import enum

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class HevyImportKind(enum.StrEnum):
    workouts = "workouts"
    measurements = "measurements"


class HevyImportRecord(Base, TimestampMixin):
    """One row per Hevy import that actually ran -- a duplicate caught before
    running (see `dinatos_backend.services.hevy_import.find_previous_import`)
    is never recorded here. `created_at` is the import time.

    Duplicate detection is scoped per `owner_id`: two different accounts
    uploading the same export (or the same account's file, coincidentally
    identical to another's) are unrelated imports, not duplicates of each
    other.
    """

    __tablename__ = "hevy_import_records"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[HevyImportKind] = mapped_column(Enum(HevyImportKind), index=True)
    content_hash: Mapped[str] = mapped_column(String(64), index=True)
    filename: Mapped[str | None] = mapped_column(String(255))
    activities_created: Mapped[int | None]
    exercises_created: Mapped[int | None]
    measurements_created: Mapped[int | None]
