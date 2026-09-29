from datetime import datetime

import pytest

from dinatos_mcp import server
from dinatos_mcp.client import DinatosClient
from dinatos_mcp.config import Settings
from dinatos_mcp.schemas import ActivityExerciseInput, WorkoutExerciseInput


@pytest.fixture
def _use_test_client(monkeypatch: pytest.MonkeyPatch, client: DinatosClient) -> None:
    """Every tool calls `server.get_client()` -- point it at the fixture's
    in-process backend instead of a real DinatosClient built from env vars.
    Opt-in (not autouse) since `test_get_client_builds_from_settings` below
    needs the real, un-patched function.
    """
    monkeypatch.setattr(server, "get_client", lambda: client)


async def test_tools_are_registered_with_descriptions() -> None:
    tools = await server.mcp.list_tools()
    names = {tool.name for tool in tools}
    assert names == {
        "list_exercises",
        "create_exercise",
        "list_workouts",
        "create_workout",
        "list_activities",
        "log_activity",
    }
    assert all(tool.description for tool in tools)


@pytest.mark.usefixtures("_use_test_client")
async def test_create_exercise_tool() -> None:
    exercise = await server.create_exercise("Deadlift (Barbell)")
    assert exercise["name"] == "Deadlift (Barbell)"

    exercises = await server.list_exercises(search="dead")
    assert [item["name"] for item in exercises] == ["Deadlift (Barbell)"]


@pytest.mark.usefixtures("_use_test_client")
async def test_create_workout_tool() -> None:
    exercise = await server.create_exercise("Overhead Press")
    workout = await server.create_workout(
        "Push day", [WorkoutExerciseInput(exercise_id=exercise["id"])]
    )
    assert workout["name"] == "Push day"

    workouts = await server.list_workouts()
    assert [w["name"] for w in workouts] == ["Push day"]


@pytest.mark.usefixtures("_use_test_client")
async def test_log_activity_tool() -> None:
    exercise = await server.create_exercise("Pull-up")
    activity = await server.log_activity(
        "Morning session",
        datetime.fromisoformat("2026-09-25T07:00:00Z"),
        [ActivityExerciseInput(exercise_id=exercise["id"])],
    )
    assert activity["title"] == "Morning session"

    activities = await server.list_activities()
    assert [a["title"] for a in activities] == ["Morning session"]


async def test_get_client_builds_from_settings(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DINATOS_MCP_TOKEN", "a-token")
    server.get_client.cache_clear()
    try:
        built = server.get_client()
        assert isinstance(built, DinatosClient)
        assert server.get_client() is built
    finally:
        await built.aclose()
        server.get_client.cache_clear()


async def test_dinatos_client_from_settings_carries_base_url_and_token() -> None:
    settings = Settings(base_url="http://example.test", token="a-token")
    built = DinatosClient.from_settings(settings)
    try:
        assert str(built.http.base_url) == "http://example.test"
        assert built.http.headers["Authorization"] == "Bearer a-token"
    finally:
        await built.aclose()
