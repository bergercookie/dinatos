from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class PlannedWorkout(Base, TimestampMixin):
    """A routine (or an ad-hoc session) the person intends to do at a given
    future time -- one entry of their training calendar.

    Deliberately not an `Activity`: an activity is what was *done* and feeds
    every stat, so a plan must never count until it is actually performed.
    `completed_activity_id` is the link made when a workout started from the
    plan is saved; deleting that activity merely un-completes the plan.
    """

    __tablename__ = "planned_workouts"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    routine_id: Mapped[int | None] = mapped_column(ForeignKey("routines.id", ondelete="SET NULL"))
    title: Mapped[str] = mapped_column(String(200))
    notes: Mapped[str | None] = mapped_column(String(2000))
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    duration_minutes: Mapped[int] = mapped_column(default=60)
    # How long before `scheduled_at` the phone reminds the person; `None`
    # means no reminder at all. Also written into the ICS feed as a VALARM.
    reminder_minutes: Mapped[int | None] = mapped_column(default=30)
    completed_activity_id: Mapped[int | None] = mapped_column(
        ForeignKey("activities.id", ondelete="SET NULL")
    )
