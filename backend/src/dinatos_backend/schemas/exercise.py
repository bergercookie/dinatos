from datetime import datetime

from pydantic import BaseModel, ConfigDict

from dinatos_backend.models.exercise import Equipment, MuscleGroup
from dinatos_backend.models.routine import SetType


class ExerciseBase(BaseModel):
    name: str
    tracks_weight: bool = True
    tracks_reps: bool = True
    tracks_distance: bool = False
    tracks_duration: bool = False
    equipment: Equipment | None = None
    primary_muscles: list[MuscleGroup] = []
    secondary_muscles: list[MuscleGroup] = []


class ExerciseCreate(ExerciseBase):
    pass


class ExerciseUpdate(BaseModel):
    name: str | None = None
    tracks_weight: bool | None = None
    tracks_reps: bool | None = None
    tracks_distance: bool | None = None
    tracks_duration: bool | None = None
    equipment: Equipment | None = None
    primary_muscles: list[MuscleGroup] | None = None
    secondary_muscles: list[MuscleGroup] | None = None


class ExerciseRead(ExerciseBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    # Server-controlled, never accepted on create/update (see ExerciseCreate/
    # ExerciseUpdate above) -- whether a client could set it is exactly what
    # would let the shipped catalog be spoofed as editable.
    is_custom: bool


class ExerciseRecordsRead(BaseModel):
    """The caller's own all-time bests for this exercise, across every past
    `ActivitySet` logged against it -- `None` for a field means no past set
    ever recorded that measure at all, not that it was beaten. Used to
    detect a new personal record at the end of a live workout (see
    `api.routers.exercises.get_exercise_records`).
    """

    max_weight_kg: float | None
    max_reps: int | None


class ExerciseHistorySet(BaseModel):
    set_type: SetType
    weight_kg: float | None
    reps: int | None
    distance_km: float | None
    duration_seconds: int | None


class ExerciseHistoryEntry(BaseModel):
    """One past session's worth of an exercise: every set the caller logged
    against it in a single activity (an exercise appearing twice in one
    activity -- e.g. in two supersets -- is merged into one entry). What the
    live workout's "last time" hint, the overload suggestion and the progress
    chart are all computed from, client-side.
    """

    activity_id: int
    activity_title: str
    started_at: datetime
    sets: list[ExerciseHistorySet]


class ExerciseTutorialRead(BaseModel):
    """Mirrors `services.tutorials.base.ExerciseTutorial` -- whichever
    provider produced it (see `source`), the shape is the same either way.

    Deliberately untyped (`str`), unlike `Exercise`'s own `equipment`/
    `primary_muscles`/`secondary_muscles`: this is third-party tutorial-
    provider content, not persisted, and a provider's vocabulary (see
    `services.tutorials.workoutx`) doesn't necessarily line up with the
    vendored dataset `MuscleGroup`/`Equipment` were built from.
    """

    model_config = ConfigDict(from_attributes=True)

    source: str
    gif_urls: list[str]
    instructions: list[str]
    equipment: str | None
    primary_muscles: list[str]
    secondary_muscles: list[str]
