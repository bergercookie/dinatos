from sqlalchemy import JSON, String
from sqlalchemy.orm import Mapped, mapped_column

from dinatos_backend.models.base import Base, TimestampMixin


class Exercise(Base, TimestampMixin):
    """A named movement in the catalog, e.g. "Squat (Barbell)".

    The `tracks_*` flags are advisory metadata for the UI and watch app --
    which fields to show when logging a set -- not a hard constraint on what
    a set may record.

    `is_custom` is False only for the shipped, seeded catalog (see
    `services.exercise.bootstrap_default_exercises`) -- a widely-agreed-upon
    staple set that stays identical across instances so exercise names line
    up with tutorial-provider lookups and imported data. It defaults to True
    because every other way an `Exercise` row comes into existence (this
    router's create endpoint, a Hevy import) is a person adding their own.
    Editing or deleting a row is only ever allowed while this is True -- see
    `api.routers.exercises`.

    `primary_muscles`/`secondary_muscles` use the same free-text muscle
    names as `services.tutorials.base.ExerciseTutorial` (indeed, the shipped
    catalog's values come straight from the same vendored
    `free_exercise_db.json` entry -- see `services.exercise`) rather than a
    closed enum: a per-exercise tag list has no need for a native DB enum
    type (and the migration-downgrade footguns that come with one -- see
    AGENTS.md), and keeping the taxonomy open lets a person's own custom
    exercise use whatever muscle name they like.
    """

    __tablename__ = "exercises"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), unique=True, index=True)
    tracks_weight: Mapped[bool] = mapped_column(default=True)
    tracks_reps: Mapped[bool] = mapped_column(default=True)
    tracks_distance: Mapped[bool] = mapped_column(default=False)
    tracks_duration: Mapped[bool] = mapped_column(default=False)
    is_custom: Mapped[bool] = mapped_column(default=True)
    primary_muscles: Mapped[list[str]] = mapped_column(JSON, default=list)
    secondary_muscles: Mapped[list[str]] = mapped_column(JSON, default=list)
