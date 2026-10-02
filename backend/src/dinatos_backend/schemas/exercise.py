from pydantic import BaseModel, ConfigDict


class ExerciseBase(BaseModel):
    name: str
    tracks_weight: bool = True
    tracks_reps: bool = True
    tracks_distance: bool = False
    tracks_duration: bool = False
    primary_muscles: list[str] = []
    secondary_muscles: list[str] = []


class ExerciseCreate(ExerciseBase):
    pass


class ExerciseUpdate(BaseModel):
    name: str | None = None
    tracks_weight: bool | None = None
    tracks_reps: bool | None = None
    tracks_distance: bool | None = None
    tracks_duration: bool | None = None
    primary_muscles: list[str] | None = None
    secondary_muscles: list[str] | None = None


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


class ExerciseTutorialRead(BaseModel):
    """Mirrors `services.tutorials.base.ExerciseTutorial` -- whichever
    provider produced it (see `source`), the shape is the same either way.
    """

    model_config = ConfigDict(from_attributes=True)

    source: str
    gif_urls: list[str]
    instructions: list[str]
    equipment: str | None
    primary_muscles: list[str]
    secondary_muscles: list[str]
