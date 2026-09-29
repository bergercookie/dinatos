"""FastMCP tool registrations -- thin wrappers over `DinatosClient`.

Kept deliberately thin: the actual HTTP request/response and error mapping
lives in `client.py`, tested directly (see tests/test_client.py) against a
real backend app over an in-memory ASGI transport. These wrappers exist to
register with FastMCP and give each tool its own name and docstring, which
FastMCP turns into the tool description an LLM harness actually sees.
"""

from datetime import datetime
from functools import lru_cache
from typing import Any

from mcp.server.fastmcp import FastMCP

from dinatos_mcp.client import DinatosClient
from dinatos_mcp.config import get_settings
from dinatos_mcp.schemas import ActivityExerciseInput, WorkoutExerciseInput

mcp = FastMCP(
    "dinatos",
    instructions=(
        "Manage a Dinatos workout tracker instance: browse and add exercises, "
        "create workout templates, and log activities. Look up exercise ids "
        "with list_exercises before creating a workout or logging an activity "
        "that references one."
    ),
)


@lru_cache
def get_client() -> DinatosClient:
    return DinatosClient.from_settings(get_settings())


@mcp.tool()
async def list_exercises(search: str | None = None) -> list[dict[str, Any]]:
    """List the exercise catalog, optionally filtered by a case-insensitive
    name search. Use this to find an exercise's id before referencing it
    from create_workout or log_activity.
    """
    return await get_client().list_exercises(search)


@mcp.tool()
async def create_exercise(
    name: str,
    tracks_weight: bool = True,
    tracks_reps: bool = True,
    tracks_distance: bool = False,
    tracks_duration: bool = False,
) -> dict[str, Any]:
    """Add a new exercise to the shared catalog. The tracks_* flags say
    which fields are relevant when logging a set of it (e.g. a run tracks
    distance and duration, not weight and reps).
    """
    return await get_client().create_exercise(
        name,
        tracks_weight=tracks_weight,
        tracks_reps=tracks_reps,
        tracks_distance=tracks_distance,
        tracks_duration=tracks_duration,
    )


@mcp.tool()
async def list_workouts() -> list[dict[str, Any]]:
    """List your saved workout templates, with their prescribed exercises and sets."""
    return await get_client().list_workouts()


@mcp.tool()
async def create_workout(
    name: str, exercises: list[WorkoutExerciseInput], description: str | None = None
) -> dict[str, Any]:
    """Create a saved workout template: a name plus a prescribed list of
    exercises and sets. Sets here are targets (target_weight_kg,
    target_reps, ...), not performed values -- use log_activity for those.
    """
    return await get_client().create_workout(name, exercises, description=description)


@mcp.tool()
async def list_activities(
    since: datetime | None = None, until: datetime | None = None
) -> list[dict[str, Any]]:
    """List logged activities (performed sessions), most recent first,
    optionally bounded by start time.
    """
    return await get_client().list_activities(since, until)


@mcp.tool()
async def log_activity(
    title: str,
    started_at: datetime,
    exercises: list[ActivityExerciseInput],
    description: str | None = None,
    ended_at: datetime | None = None,
    workout_id: int | None = None,
) -> dict[str, Any]:
    """Log a completed activity: what was actually done, and when. May
    reference one of your own workout templates by id (workout_id) -- not
    someone else's, and not required for an ad-hoc session.
    """
    return await get_client().log_activity(
        title,
        started_at,
        exercises,
        description=description,
        ended_at=ended_at,
        workout_id=workout_id,
    )
