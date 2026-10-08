"""The MCP server hosted at /mcp: API-key auth, the tools, and that it can only
do what the key's owner could do through the API.
"""

import asyncio
import json
from collections.abc import AsyncIterator
from typing import Any

import pytest
from httpx2 import AsyncClient

from backup_seed import register
from dinatos_backend.api.mcp import mcp_gateway

_HEADERS = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}


@pytest.fixture(autouse=True)
async def _mcp_running() -> AsyncIterator[None]:
    """Runs the gateway in a task of its own: its transport's task group must be
    entered and left by the same task, which a fixture's setup and teardown are not.
    """
    started, stop = asyncio.Event(), asyncio.Event()

    async def run() -> None:
        async with mcp_gateway.running():
            started.set()
            await stop.wait()

    task = asyncio.create_task(run())
    await started.wait()
    yield
    stop.set()
    await task


async def _api_key(client: AsyncClient, name: str = "MCP") -> str:
    response = await client.post("/api-keys", json={"name": name})
    assert response.status_code == 201, response.text
    key: str = response.json()["key"]
    return key


async def _rpc(
    client: AsyncClient, key: str | None, method: str, params: dict[str, Any] | None = None
) -> Any:
    headers = dict(_HEADERS)
    headers["Authorization"] = f"Bearer {key}" if key is not None else ""
    return await client.post(
        "/mcp",
        headers=headers,
        json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}},
    )


async def _call(client: AsyncClient, key: str, tool: str, **arguments: Any) -> dict[str, Any]:
    response = await _rpc(client, key, "tools/call", {"name": tool, "arguments": arguments})
    assert response.status_code == 200, response.text
    result: dict[str, Any] = response.json()["result"]
    return result


def _data(result: dict[str, Any]) -> Any:
    """A tool's return value, from MCP's structured or text content."""
    if result.get("structuredContent") is not None:
        structured = result["structuredContent"]
        return structured.get("result", structured)
    return json.loads(result["content"][0]["text"])


async def test_lists_the_tools(client: AsyncClient) -> None:
    key = await _api_key(client)
    response = await _rpc(client, key, "tools/list")
    assert response.status_code == 200, response.text
    names = {tool["name"] for tool in response.json()["result"]["tools"]}
    assert names == {
        "list_exercises",
        "create_exercise",
        "list_routines",
        "create_routine",
        "list_activities",
        "log_activity",
        "list_planned_workouts",
        "schedule_workout",
        "update_planned_workout",
        "delete_planned_workout",
        "get_persona_stats",
    }


@pytest.mark.parametrize("key", [None, "", "dnk_nonsense", "not-a-key"])
async def test_a_missing_or_wrong_key_is_rejected(client: AsyncClient, key: str | None) -> None:
    response = await _rpc(client, key, "tools/list")
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


async def test_a_login_token_is_not_accepted(client: AsyncClient) -> None:
    login_token = client.headers["Authorization"].removeprefix("Bearer ")
    assert (await _rpc(client, login_token, "tools/list")).status_code == 401


async def test_a_deleted_key_stops_working(client: AsyncClient) -> None:
    created = (await client.post("/api-keys", json={"name": "temp"})).json()
    assert (await _rpc(client, created["key"], "tools/list")).status_code == 200
    await client.delete(f"/api-keys/{created['id']}")
    assert (await _rpc(client, created["key"], "tools/list")).status_code == 401


async def test_the_endpoint_answers_without_a_trailing_slash_redirect(
    client: AsyncClient,
) -> None:
    key = await _api_key(client)
    headers = {**_HEADERS, "Authorization": f"Bearer {key}"}
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}
    for path in ("/mcp", "/mcp/"):
        response = await client.post(path, headers=headers, json=body)
        assert response.status_code == 200, (path, response.status_code)


async def test_exercises_routines_and_activities_round_trip(client: AsyncClient) -> None:
    key = await _api_key(client)

    created = _data(await _call(client, key, "create_exercise", name="Sled Drag"))
    assert created["name"] == "Sled Drag"
    found = _data(await _call(client, key, "list_exercises", search="sled"))
    assert [e["name"] for e in found] == ["Sled Drag"]
    exercise_id = created["id"]

    routine = _data(
        await _call(
            client,
            key,
            "create_routine",
            name="Sleds",
            description="Heavy",
            exercises=[{"exercise_id": exercise_id, "sets": [{"target_reps": 5}]}],
        )
    )
    assert routine["name"] == "Sleds"
    routines = _data(await _call(client, key, "list_routines"))
    assert "Sleds" in [r["name"] for r in routines]

    activity = _data(
        await _call(
            client,
            key,
            "log_activity",
            title="Sled day",
            started_at="2026-10-01T10:00:00Z",
            exercises=[
                {
                    "exercise_id": exercise_id,
                    "sets": [{"weight_kg": 100, "reps": 5}, {"reps": 5, "completed": False}],
                }
            ],
        )
    )
    assert [s["completed"] for s in activity["exercises"][0]["sets"]] == [True, False]
    listed = _data(await _call(client, key, "list_activities", since="2026-09-01T00:00:00Z"))
    assert [a["title"] for a in listed] == ["Sled day"]
    # ...and the same data is there through the REST API, for the same person.
    assert len((await client.get("/activities")).json()) == 1


async def test_a_tool_reports_the_apis_refusal(client: AsyncClient) -> None:
    key = await _api_key(client)
    result = await _call(client, key, "create_exercise", name="Dup")
    assert not result.get("isError")
    again = await _call(client, key, "create_exercise", name="Dup")
    assert again["isError"] is True


async def test_the_key_only_ever_sees_its_owners_data(
    client: AsyncClient, anonymous_client: AsyncClient
) -> None:
    other = await register(anonymous_client, "other@example.com")
    await anonymous_client.post(
        "/routines", json={"name": "Not yours", "exercises": []}, headers=other.headers
    )
    key = await _api_key(client)
    routines = _data(await _call(client, key, "list_routines"))
    assert "Not yours" not in [r["name"] for r in routines]


async def test_persona_stats_for_someone_with_nothing_logged(client: AsyncClient) -> None:
    key = await _api_key(client)
    stats = _data(await _call(client, key, "get_persona_stats"))
    assert stats["range"] == "quarter"
    assert stats["best_body_match"] is None
    assert stats["best_training_match"] is None
    assert "height (in your profile)" in stats["missing_inputs"]
    assert {p["id"] for p in stats["personas"]} == {
        "sprinter",
        "distance_runner",
        "weightlifter",
        "powerlifter",
        "bodybuilder",
        "gymnast",
    }


async def test_persona_stats_use_the_persons_data(client: AsyncClient) -> None:
    key = await _api_key(client)
    await client.patch("/profile", json={"height_cm": 181})
    await client.post(
        "/measurements",
        json={
            "measured_at": "2026-10-01T08:00:00Z",
            "weight_kg": 82,
            "fat_percent": 14,
            "waist_cm": 84,
            "shoulder_cm": 122,
        },
    )
    squat = (await client.post("/exercises", json={"name": "Heavy Squat"})).json()["id"]
    from datetime import UTC, datetime, timedelta

    started = (datetime.now(UTC) - timedelta(days=2)).isoformat()
    await client.post(
        "/activities",
        json={
            "title": "Heavy",
            "started_at": started,
            "exercises": [
                {"exercise_id": squat, "sets": [{"weight_kg": 150, "reps": 3} for _ in range(12)]},
                {"exercise_id": squat, "sets": [{"weight_kg": 150, "reps": 3, "completed": False}]},
            ],
        },
    )

    stats = _data(await _call(client, key, "get_persona_stats", range="month"))
    assert stats["range"] == "month"
    assert stats["training_units"] == 12  # the unticked set is not counted
    assert stats["training_share"]["max_strength"] == 1.0
    assert stats["best_training_match"] == "powerlifter"
    assert set(stats["body_features"]) >= {"height", "ffmi", "fat_percent", "waist_to_height"}
    assert all(p["body_score"] is not None for p in stats["personas"])


async def test_an_invalid_range_is_rejected(client: AsyncClient) -> None:
    key = await _api_key(client)
    result = await _call(client, key, "get_persona_stats", range="decade")
    assert result["isError"] is True


async def test_a_refusal_from_the_api_comes_back_as_a_tool_error(client: AsyncClient) -> None:
    key = await _api_key(client)
    result = await _call(
        client,
        key,
        "log_activity",
        title="Ghost",
        started_at="2026-10-01T10:00:00Z",
        exercises=[],
        routine_id=999999,
    )
    assert result["isError"] is True
    assert "404" in result["content"][0]["text"]
    assert "routine not found" in result["content"][0]["text"]


async def test_schedule_read_update_and_delete_a_planned_workout(client: AsyncClient) -> None:
    key = await _api_key(client)
    routine = _data(await _call(client, key, "create_routine", name="Pull Day", exercises=[]))

    plan = _data(
        await _call(
            client,
            key,
            "schedule_workout",
            scheduled_at="2030-01-05T07:30:00+00:00",
            routine_id=routine["id"],
        )
    )
    assert plan["title"] == "Pull Day"
    assert plan["reminder_minutes"] == 30

    listed = _data(await _call(client, key, "list_planned_workouts"))
    assert [p["id"] for p in listed] == [plan["id"]]
    later = _data(
        await _call(client, key, "list_planned_workouts", since="2031-01-01T00:00:00+00:00")
    )
    assert later == []

    moved = _data(
        await _call(
            client,
            key,
            "update_planned_workout",
            planned_workout_id=plan["id"],
            scheduled_at="2030-01-06T18:00:00+00:00",
            notes="Heavy",
            remove_reminder=True,
        )
    )
    assert moved["scheduled_at"].startswith("2030-01-06T18:00:00")
    assert moved["notes"] == "Heavy"
    assert moved["reminder_minutes"] is None
    assert moved["title"] == "Pull Day"

    # Without remove_reminder, an unmentioned reminder is left alone.
    renamed = _data(
        await _call(
            client, key, "update_planned_workout", planned_workout_id=plan["id"], title="Back day"
        )
    )
    assert renamed["title"] == "Back day"
    assert renamed["reminder_minutes"] is None

    deleted = _data(
        await _call(client, key, "delete_planned_workout", planned_workout_id=plan["id"])
    )
    assert deleted == {"deleted": plan["id"]}
    assert _data(await _call(client, key, "list_planned_workouts")) == []
