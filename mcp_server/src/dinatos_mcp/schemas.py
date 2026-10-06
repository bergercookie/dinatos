"""Nested-input shapes for the `create_routine`/`log_activity` tools.

Deliberately not imported from `dinatos_backend.schemas`: this package talks
to that API over HTTP, the same as any other client, rather than depending
on the backend's own Python package at runtime (only its tests do, to spin
up the real app in-process -- see tests/conftest.py). These mirror the
backend's `RoutineSetCreate`/`ActivitySetCreate` etc. shapes closely enough
to round-trip through `POST /routines` and `POST /activities` unchanged.
"""

import enum

from pydantic import BaseModel


class SetType(enum.StrEnum):
    normal = "normal"
    warmup = "warmup"
    dropset = "dropset"
    failure = "failure"


class RoutineSetInput(BaseModel):
    """A prescribed set on a routine template -- targets, not what was
    actually done (see `ActivitySetInput`)."""

    set_type: SetType = SetType.normal
    target_weight_kg: float | None = None
    target_reps: int | None = None
    target_distance_km: float | None = None
    target_duration_seconds: int | None = None


class RoutineExerciseInput(BaseModel):
    exercise_id: int
    superset_group: int | None = None
    notes: str | None = None
    sets: list[RoutineSetInput] = []


class ActivitySetInput(BaseModel):
    """A set as actually performed, logged against an activity."""

    set_type: SetType = SetType.normal
    weight_kg: float | None = None
    reps: int | None = None
    distance_km: float | None = None
    duration_seconds: int | None = None
    # A set you are logging after the fact was done; pass false for one that was
    # planned but not performed.
    completed: bool = True


class ActivityExerciseInput(BaseModel):
    exercise_id: int
    superset_group: int | None = None
    notes: str | None = None
    sets: list[ActivitySetInput] = []
