from __future__ import annotations

import enum

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from dinatos_backend.models.base import Base, TimestampMixin
from dinatos_backend.models.exercise import Exercise


class SetType(enum.StrEnum):
    normal = "normal"
    warmup = "warmup"
    dropset = "dropset"
    failure = "failure"


class Routine(Base, TimestampMixin):
    """A saved routine template, e.g. "Upper body"."""

    __tablename__ = "routines"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(String(2000))

    exercises: Mapped[list[RoutineExercise]] = relationship(
        back_populates="routine",
        order_by="RoutineExercise.position",
        cascade="all, delete-orphan",
    )


class RoutineExercise(Base):
    """One exercise's place in a routine template, with its prescribed sets."""

    __tablename__ = "routine_exercises"

    id: Mapped[int] = mapped_column(primary_key=True)
    routine_id: Mapped[int] = mapped_column(ForeignKey("routines.id", ondelete="CASCADE"))
    exercise_id: Mapped[int] = mapped_column(ForeignKey("exercises.id"))
    position: Mapped[int]
    # Exercises sharing a `superset_group` are performed back-to-back; copied
    # onto the activity when a workout is started from this routine.
    superset_group: Mapped[int | None]
    notes: Mapped[str | None] = mapped_column(String(2000))

    routine: Mapped[Routine] = relationship(back_populates="exercises")
    exercise: Mapped[Exercise] = relationship()
    sets: Mapped[list[RoutineSet]] = relationship(
        back_populates="routine_exercise",
        order_by="RoutineSet.position",
        cascade="all, delete-orphan",
    )


class RoutineSet(Base):
    """A prescribed set: targets, not what was actually done -- see `ActivitySet`."""

    __tablename__ = "routine_sets"

    id: Mapped[int] = mapped_column(primary_key=True)
    routine_exercise_id: Mapped[int] = mapped_column(
        ForeignKey("routine_exercises.id", ondelete="CASCADE")
    )
    position: Mapped[int]
    set_type: Mapped[SetType] = mapped_column(Enum(SetType), default=SetType.normal)
    target_weight_kg: Mapped[float | None]
    target_reps: Mapped[int | None]
    target_distance_km: Mapped[float | None]
    target_duration_seconds: Mapped[int | None]

    routine_exercise: Mapped[RoutineExercise] = relationship(back_populates="sets")
