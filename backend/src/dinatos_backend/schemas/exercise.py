from pydantic import BaseModel, ConfigDict


class ExerciseBase(BaseModel):
    name: str
    tracks_weight: bool = True
    tracks_reps: bool = True
    tracks_distance: bool = False
    tracks_duration: bool = False


class ExerciseCreate(ExerciseBase):
    pass


class ExerciseUpdate(BaseModel):
    name: str | None = None
    tracks_weight: bool | None = None
    tracks_reps: bool | None = None
    tracks_distance: bool | None = None
    tracks_duration: bool | None = None


class ExerciseRead(ExerciseBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    # Server-controlled, never accepted on create/update (see ExerciseCreate/
    # ExerciseUpdate above) -- whether a client could set it is exactly what
    # would let the shipped catalog be spoofed as editable.
    is_custom: bool


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
