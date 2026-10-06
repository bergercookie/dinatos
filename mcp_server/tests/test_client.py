import asyncio
from datetime import datetime

import httpx
import pytest
from httpx import ASGITransport

from dinatos_mcp.client import DinatosAPIError, DinatosClient, DinatosConfigError
from dinatos_mcp.config import Settings
from dinatos_mcp.schemas import (
    ActivityExerciseInput,
    ActivitySetInput,
    RoutineExerciseInput,
    RoutineSetInput,
    SetType,
)

TEST_USER_EMAIL = "test@example.com"
TEST_USER_PASSWORD = "hunter22"


async def _create_exercise(client: DinatosClient, name: str = "Squat (Barbell)") -> int:
    created = await client.create_exercise(name)
    exercise_id: int = created["id"]
    return exercise_id


async def test_create_and_list_exercises(client: DinatosClient) -> None:
    await client.create_exercise("Bench Press", tracks_distance=False)
    await client.create_exercise(
        "5k Run", tracks_weight=False, tracks_reps=False, tracks_distance=True
    )

    all_exercises = await client.list_exercises()
    assert {item["name"] for item in all_exercises} == {"Bench Press", "5k Run"}

    filtered = await client.list_exercises(search="bench")
    assert [item["name"] for item in filtered] == ["Bench Press"]

    run = next(item for item in all_exercises if item["name"] == "5k Run")
    assert run["tracks_distance"] is True
    assert run["tracks_weight"] is False


async def test_create_routine_with_nested_exercises_and_sets(client: DinatosClient) -> None:
    exercise_id = await _create_exercise(client)

    routine = await client.create_routine(
        "Leg day",
        [
            RoutineExerciseInput(
                exercise_id=exercise_id,
                notes="go deep",
                sets=[
                    RoutineSetInput(set_type=SetType.warmup, target_reps=10, target_weight_kg=20),
                    RoutineSetInput(set_type=SetType.normal, target_reps=5, target_weight_kg=60),
                ],
            )
        ],
        description="Squats and lunges",
    )

    assert routine["name"] == "Leg day"
    assert routine["description"] == "Squats and lunges"
    assert len(routine["exercises"]) == 1
    assert routine["exercises"][0]["notes"] == "go deep"
    assert [s["set_type"] for s in routine["exercises"][0]["sets"]] == ["warmup", "normal"]

    routines = await client.list_routines()
    assert [w["name"] for w in routines] == ["Leg day"]


async def test_log_activity_with_nested_exercises_and_sets(client: DinatosClient) -> None:
    exercise_id = await _create_exercise(client)

    activity = await client.log_activity(
        "Evening workout",
        started_at=datetime.fromisoformat("2026-09-24T21:13:00Z"),
        exercises=[
            ActivityExerciseInput(
                exercise_id=exercise_id,
                sets=[
                    ActivitySetInput(set_type=SetType.normal, weight_kg=40, reps=10),
                    ActivitySetInput(set_type=SetType.dropset, weight_kg=30, reps=12),
                ],
            )
        ],
    )

    assert activity["title"] == "Evening workout"
    assert len(activity["exercises"][0]["sets"]) == 2
    assert activity["exercises"][0]["sets"][1]["set_type"] == "dropset"

    activities = await client.list_activities()
    assert [a["title"] for a in activities] == ["Evening workout"]


async def test_log_activity_rejects_unowned_routine_id(client: DinatosClient) -> None:
    with pytest.raises(DinatosAPIError) as excinfo:
        await client.log_activity(
            "Ad-hoc session",
            started_at=datetime.fromisoformat("2026-09-24T21:13:00Z"),
            exercises=[],
            routine_id=999,
        )
    assert excinfo.value.status_code == 404
    assert "routine" in excinfo.value.detail


async def test_without_credentials_raises_config_error(backend_transport: ASGITransport) -> None:
    async with httpx.AsyncClient(transport=backend_transport, base_url="http://test") as http:
        client = DinatosClient(http)
        with pytest.raises(DinatosConfigError):
            await client.list_exercises()


async def test_logs_in_lazily_with_email_and_password(
    backend_transport: ASGITransport,
    registered_user: None,  # noqa: ARG001 -- depended on for its side effect, not its value
) -> None:
    async with httpx.AsyncClient(transport=backend_transport, base_url="http://test") as http:
        client = DinatosClient(http, email=TEST_USER_EMAIL, password=TEST_USER_PASSWORD)
        assert "Authorization" not in http.headers

        exercises = await client.list_exercises()

        assert exercises == []
        assert "Authorization" in http.headers


async def test_bad_password_raises_api_error(
    backend_transport: ASGITransport,
    registered_user: None,  # noqa: ARG001 -- depended on for its side effect, not its value
) -> None:
    async with httpx.AsyncClient(transport=backend_transport, base_url="http://test") as http:
        client = DinatosClient(http, email=TEST_USER_EMAIL, password="wrong-password")
        with pytest.raises(DinatosAPIError) as excinfo:
            await client.list_exercises()
        assert excinfo.value.status_code == 401


async def test_concurrent_calls_log_in_only_once(
    backend_transport: ASGITransport,
    registered_user: None,  # noqa: ARG001 -- depended on for its side effect, not its value
) -> None:
    async with httpx.AsyncClient(transport=backend_transport, base_url="http://test") as http:
        client = DinatosClient(http, email=TEST_USER_EMAIL, password=TEST_USER_PASSWORD)

        first, second = await asyncio.gather(client.list_exercises(), client.list_exercises())

        assert first == []
        assert second == []


async def test_from_settings_without_a_token_does_not_set_the_header() -> None:
    settings = Settings(email=TEST_USER_EMAIL, password=TEST_USER_PASSWORD)
    client = DinatosClient.from_settings(settings)
    try:
        assert "Authorization" not in client.http.headers
    finally:
        await client.aclose()
