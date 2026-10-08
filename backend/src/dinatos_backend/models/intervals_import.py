from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class IntervalsImportedActivity(Base, TimestampMixin):
    """One row per Intervals.icu activity that has been imported, and the
    Dinatos activity it became.

    Unlike a Hevy import -- a CSV file, told apart from another only by a hash
    of its whole content (see `HevyImportRecord`) -- every Intervals.icu
    activity has a stable id of its own, so duplicates are caught per activity:
    importing a selection a second time (or overlapping date ranges) never
    creates a second copy unless the caller says `force`. `created_at` is when
    it was imported; a forced re-import repoints the row at the new activity
    rather than adding a second one.

    A row only counts while its `activity_id` still names an existing
    activity (the services join on it): deleting the imported activity in the
    app frees it to be imported again, with no cascade needed to make that so
    -- sqlite, which the tests run on, has none.
    """

    __tablename__ = "intervals_imported_activities"
    __table_args__ = (
        UniqueConstraint("owner_id", "intervals_id", name="uq_intervals_imported_owner_activity"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    # Intervals.icu's own activity id ("i1234567", or a bare number for older
    # ones), always stored as text. Scoped per `owner_id`: two accounts
    # importing the same Intervals.icu activity are unrelated imports.
    intervals_id: Mapped[str] = mapped_column(String(64))
    activity_id: Mapped[int] = mapped_column(
        ForeignKey("activities.id", ondelete="CASCADE"), index=True
    )
    # When the activity happened on Intervals.icu's side, kept so the row is
    # meaningful on its own (e.g. in a backup) without joining `activities`.
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
