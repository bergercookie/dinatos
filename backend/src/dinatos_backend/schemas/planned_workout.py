from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

# A day is the longest a single plan can sensibly block out; a week the
# furthest ahead a reminder makes sense (and what calendar apps allow).
MAX_DURATION_MINUTES = 24 * 60
MAX_REMINDER_MINUTES = 7 * 24 * 60


class PlannedWorkoutBase(BaseModel):
    """What can be set on a planned workout. `title` falls back to the
    routine's name when a routine is given and no title is.
    """

    title: str | None = Field(default=None, max_length=200)
    notes: str | None = Field(default=None, max_length=2000)
    scheduled_at: datetime
    routine_id: int | None = None
    duration_minutes: int = Field(default=60, ge=5, le=MAX_DURATION_MINUTES)
    # Minutes before `scheduled_at` to remind; null = no reminder.
    reminder_minutes: int | None = Field(default=30, ge=0, le=MAX_REMINDER_MINUTES)

    @field_validator("title")
    @classmethod
    def _blank_title_is_none(cls, value: str | None) -> str | None:
        value = value.strip() if value else None
        return value or None


class PlannedWorkoutCreate(PlannedWorkoutBase):
    """Also used to replace a planned workout in full via `PUT`."""


class PlannedWorkoutUpdate(BaseModel):
    """`PATCH`: only the fields sent change (null clears an optional one)."""

    title: str | None = Field(default=None, min_length=1, max_length=200)
    notes: str | None = Field(default=None, max_length=2000)
    scheduled_at: datetime | None = None
    routine_id: int | None = None
    duration_minutes: int | None = Field(default=None, ge=5, le=MAX_DURATION_MINUTES)
    reminder_minutes: int | None = Field(default=None, ge=0, le=MAX_REMINDER_MINUTES)


class PlannedWorkoutRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    notes: str | None
    scheduled_at: datetime
    routine_id: int | None
    duration_minutes: int
    reminder_minutes: int | None
    completed_activity_id: int | None


class CalendarFeedRead(BaseModel):
    """The calendar feed's secret. `token` is null while the feed is off; the
    client builds the full URL as `<server>/calendar/<token>.ics`, since only
    it knows the address the server is reached at.
    """

    token: str | None
    path: str | None
