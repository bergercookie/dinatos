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


class Workout(Base, TimestampMixin):
    """A saved routine template, e.g. "Upper body"."""

    __tablename__ = "workouts"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(String(2000))

    exercises: Mapped[list[WorkoutExercise]] = relationship(
        back_populates="workout",
        order_by="WorkoutExercise.position",
        cascade="all, delete-orphan",
    )


class WorkoutExercise(Base):
    """One exercise's place in a workout template, with its prescribed sets."""

    __tablename__ = "workout_exercises"

    id: Mapped[int] = mapped_column(primary_key=True)
    workout_id: Mapped[int] = mapped_column(ForeignKey("workouts.id", ondelete="CASCADE"))
    exercise_id: Mapped[int] = mapped_column(ForeignKey("exercises.id"))
    position: Mapped[int]
    notes: Mapped[str | None] = mapped_column(String(2000))

    workout: Mapped[Workout] = relationship(back_populates="exercises")
    exercise: Mapped[Exercise] = relationship()
    sets: Mapped[list[WorkoutSet]] = relationship(
        back_populates="workout_exercise",
        order_by="WorkoutSet.position",
        cascade="all, delete-orphan",
    )


class WorkoutSet(Base):
    """A prescribed set: targets, not what was actually done -- see `ActivitySet`."""

    __tablename__ = "workout_sets"

    id: Mapped[int] = mapped_column(primary_key=True)
    workout_exercise_id: Mapped[int] = mapped_column(
        ForeignKey("workout_exercises.id", ondelete="CASCADE")
    )
    position: Mapped[int]
    set_type: Mapped[SetType] = mapped_column(Enum(SetType), default=SetType.normal)
    target_weight_kg: Mapped[float | None]
    target_reps: Mapped[int | None]
    target_distance_km: Mapped[float | None]
    target_duration_seconds: Mapped[int | None]

    workout_exercise: Mapped[WorkoutExercise] = relationship(back_populates="sets")
