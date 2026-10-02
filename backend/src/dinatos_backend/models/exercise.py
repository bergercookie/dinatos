from __future__ import annotations

import enum

from sqlalchemy import Enum, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from dinatos_backend.models.base import Base, TimestampMixin


class MuscleGroup(enum.StrEnum):
    """A fixed, closed vocabulary rather than free text, so that what an
    exercise trains can later be aggregated across a person's own logged
    sets (e.g. "which muscles got the most volume this week") instead of
    merely displayed. Matches the vocabulary of the vendored
    `data/free_exercise_db.json` dataset (see `services.exercise`'s
    `_default_exercises`) -- spaces normalized to underscores, since those
    can't appear in an enum member name.
    """

    abdominals = "abdominals"
    abductors = "abductors"
    adductors = "adductors"
    biceps = "biceps"
    calves = "calves"
    chest = "chest"
    forearms = "forearms"
    glutes = "glutes"
    hamstrings = "hamstrings"
    lats = "lats"
    lower_back = "lower_back"
    middle_back = "middle_back"
    neck = "neck"
    quadriceps = "quadriceps"
    shoulders = "shoulders"
    traps = "traps"
    triceps = "triceps"


class Equipment(enum.StrEnum):
    """Same closed-vocabulary reasoning as `MuscleGroup`, for what an
    exercise is performed with.
    """

    bands = "bands"
    barbell = "barbell"
    body_only = "body_only"
    cable = "cable"
    dumbbell = "dumbbell"
    e_z_curl_bar = "e_z_curl_bar"
    exercise_ball = "exercise_ball"
    foam_roll = "foam_roll"
    kettlebells = "kettlebells"
    machine = "machine"
    medicine_ball = "medicine_ball"
    other = "other"


class Exercise(Base, TimestampMixin):
    """A named movement in the catalog, e.g. "Squat (Barbell)".

    The `tracks_*` flags are advisory metadata for the UI and watch app --
    which fields to show when logging a set -- not a hard constraint on what
    a set may record.

    `equipment` and `muscles` are typed metadata about the movement itself
    (what it's trained with, and what it trains) -- `MuscleGroup`/
    `Equipment` enums rather than free text precisely so this can be
    reasoned about later (e.g. "which muscles got the most volume this
    week"), not just shown as a label. `equipment` is a single optional
    value; `muscles` is a one-to-many relationship (see `ExerciseMuscle`)
    since an exercise can have several primary and secondary muscles -- a
    join table rather than array/JSON columns since SQLite (what `just
    test` runs against) has no array type, and a closed enum keeps a typo
    or a provider's inconsistent spelling from silently creating a new,
    never-matched "muscle".

    `is_custom` is False only for the shipped, seeded catalog (see
    `services.exercise.bootstrap_default_exercises`) -- a widely-agreed-upon
    staple set that stays identical across instances so exercise names line
    up with tutorial-provider lookups and imported data. It defaults to True
    because every other way an `Exercise` row comes into existence (this
    router's create endpoint, a Hevy import) is a person adding their own.
    Editing or deleting a row is only ever allowed while this is True -- see
    `api.routers.exercises`.
    """

    __tablename__ = "exercises"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), unique=True, index=True)
    tracks_weight: Mapped[bool] = mapped_column(default=True)
    tracks_reps: Mapped[bool] = mapped_column(default=True)
    tracks_distance: Mapped[bool] = mapped_column(default=False)
    tracks_duration: Mapped[bool] = mapped_column(default=False)
    is_custom: Mapped[bool] = mapped_column(default=True)
    equipment: Mapped[Equipment | None] = mapped_column(Enum(Equipment), default=None)

    muscles: Mapped[list[ExerciseMuscle]] = relationship(
        back_populates="exercise",
        cascade="all, delete-orphan",
        order_by="ExerciseMuscle.muscle",
    )

    @property
    def primary_muscles(self) -> list[MuscleGroup]:
        return [row.muscle for row in self.muscles if row.is_primary]

    @property
    def secondary_muscles(self) -> list[MuscleGroup]:
        return [row.muscle for row in self.muscles if not row.is_primary]


class ExerciseMuscle(Base):
    """One muscle group an `Exercise` trains, and whether primarily or
    secondarily -- see `Exercise.muscles`'s docstring for why this is a
    join table rather than array/JSON columns on `Exercise` itself. Also
    what `api.routers.exercises.list_exercises`'s `muscle` filter queries
    against, to answer "which exercises train this muscle".
    """

    __tablename__ = "exercise_muscles"
    __table_args__ = (UniqueConstraint("exercise_id", "muscle"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    exercise_id: Mapped[int] = mapped_column(ForeignKey("exercises.id", ondelete="CASCADE"))
    muscle: Mapped[MuscleGroup] = mapped_column(Enum(MuscleGroup))
    is_primary: Mapped[bool] = mapped_column(default=True)

    exercise: Mapped[Exercise] = relationship(back_populates="muscles")
