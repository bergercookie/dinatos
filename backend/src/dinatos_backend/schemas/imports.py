from datetime import date, datetime
from typing import Self

from pydantic import BaseModel, Field, model_validator

from dinatos_backend.models.exercise import Equipment, MuscleGroup


class ImportedExercise(BaseModel):
    """A custom exercise this import had to create because no catalog
    exercise matched it exactly, with whatever equipment/muscles were
    *guessed* for it (see `services.hevy_exercise_infer`). The guesses are
    already saved on the exercise; the flags say which of its fields came
    from a guess rather than from the person, so the UI can ask for a review.
    """

    id: int
    name: str
    equipment: Equipment | None = None
    primary_muscles: list[MuscleGroup] = []
    secondary_muscles: list[MuscleGroup] = []
    equipment_guessed: bool = False
    muscles_guessed: bool = False


class HevyWorkoutImportResult(BaseModel):
    activities_created: int
    exercises_created: int
    # One entry per exercise counted in `exercises_created`, in file order.
    created_exercises: list[ImportedExercise] = []


class HevyMeasurementImportResult(BaseModel):
    measurements_created: int


# --- Intervals.icu -----------------------------------------------------------

# "0" is Intervals.icu's own alias for "whoever owns this API key"; otherwise an
# athlete id is "i" plus digits. Validated strictly because it goes straight
# into a URL path on the Intervals.icu API.
_ATHLETE_ID_PATTERN = r"^(0|i?[0-9]{1,20})$"


class IntervalsSource(BaseModel):
    """Where to read from: the person's own Intervals.icu account and a date
    window. The API key is used for this one request and never stored.
    """

    athlete_id: str = Field(default="0", pattern=_ATHLETE_ID_PATTERN)
    api_key: str = Field(min_length=1, max_length=200)
    oldest: date
    # Defaults to today (server date).
    newest: date | None = None

    @model_validator(mode="after")
    def _window_is_ordered(self) -> Self:
        if self.newest is not None and self.newest < self.oldest:
            raise ValueError("newest must not be before oldest")
        return self


class IntervalsActivityPreview(BaseModel):
    """One Intervals.icu activity as offered for selection."""

    id: str
    name: str
    type: str | None = None
    # None only when the activity is unimportable (it has no readable start).
    started_at: datetime | None = None
    duration_seconds: int | None = None
    distance_km: float | None = None
    # False when it can't be imported (e.g. a Strava-sourced activity, which
    # Intervals.icu's API only returns a stub for); `unimportable_reason` says why.
    importable: bool = True
    unimportable_reason: str | None = None
    # Already imported from Intervals.icu before (and still present).
    already_imported: bool = False
    imported_at: datetime | None = None
    # A Dinatos activity (typically from Hevy) starts within 30 minutes of this
    # one -- likely the same workout recorded twice.
    possible_duplicate_of: str | None = None


class IntervalsActivityList(BaseModel):
    activities: list[IntervalsActivityPreview]


class IntervalsImportRequest(IntervalsSource):
    activity_ids: list[str] = Field(min_length=1, max_length=1000)


class IntervalsImportResult(BaseModel):
    activities_created: int
    exercises_created: int
    created_exercises: list[ImportedExercise] = []
