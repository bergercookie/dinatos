from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class Exercise(Base, TimestampMixin):
    """A named movement in the catalog, e.g. "Squat (Barbell)".

    The `tracks_*` flags are advisory metadata for the UI and watch app --
    which fields to show when logging a set -- not a hard constraint on what
    a set may record.
    """

    __tablename__ = "exercises"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), unique=True, index=True)
    tracks_weight: Mapped[bool] = mapped_column(default=True)
    tracks_reps: Mapped[bool] = mapped_column(default=True)
    tracks_distance: Mapped[bool] = mapped_column(default=False)
    tracks_duration: Mapped[bool] = mapped_column(default=False)
