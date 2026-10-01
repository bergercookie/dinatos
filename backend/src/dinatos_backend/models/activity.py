from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from dinatos_backend.models.base import Base, TimestampMixin
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.models.routine import SetType


class Activity(Base, TimestampMixin):
    """A recorded gym session: what was actually done, and when.

    May reference the `Routine` template it was run from, or be `None` for an
    ephemeral session built on the spot.
    """

    __tablename__ = "activities"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    routine_id: Mapped[int | None] = mapped_column(ForeignKey("routines.id", ondelete="SET NULL"))
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(String(2000))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    exercises: Mapped[list[ActivityExercise]] = relationship(
        back_populates="activity",
        order_by="ActivityExercise.position",
        cascade="all, delete-orphan",
    )


class ActivityExercise(Base):
    """One exercise as actually performed within an activity."""

    __tablename__ = "activity_exercises"

    id: Mapped[int] = mapped_column(primary_key=True)
    activity_id: Mapped[int] = mapped_column(ForeignKey("activities.id", ondelete="CASCADE"))
    exercise_id: Mapped[int] = mapped_column(ForeignKey("exercises.id"))
    position: Mapped[int]
    # Sets sharing a `superset_group` were performed back-to-back as a
    # superset; `None` means this exercise stood on its own.
    superset_group: Mapped[int | None]
    notes: Mapped[str | None] = mapped_column(String(2000))

    activity: Mapped[Activity] = relationship(back_populates="exercises")
    exercise: Mapped[Exercise] = relationship()
    sets: Mapped[list[ActivitySet]] = relationship(
        back_populates="activity_exercise",
        order_by="ActivitySet.position",
        cascade="all, delete-orphan",
    )


class ActivitySet(Base):
    """A single completed set: whatever combination of weight, reps,
    distance and duration the exercise calls for.
    """

    __tablename__ = "activity_sets"

    id: Mapped[int] = mapped_column(primary_key=True)
    activity_exercise_id: Mapped[int] = mapped_column(
        ForeignKey("activity_exercises.id", ondelete="CASCADE")
    )
    position: Mapped[int]
    set_type: Mapped[SetType] = mapped_column(Enum(SetType), default=SetType.normal)
    weight_kg: Mapped[float | None]
    reps: Mapped[int | None]
    distance_km: Mapped[float | None]
    duration_seconds: Mapped[int | None]
    rpe: Mapped[float | None]

    activity_exercise: Mapped[ActivityExercise] = relationship(back_populates="sets")
