from httpx2 import AsyncClient


async def _create_exercise(client: AsyncClient, name: str = "Squat (Barbell)") -> int:
    response = await client.post("/exercises", json={"name": name})
    exercise_id: int = response.json()["id"]
    return exercise_id


async def test_create_activity_with_nested_exercises_and_sets(client: AsyncClient) -> None:
    exercise_id = await _create_exercise(client)

    payload = {
        "title": "Evening workout",
        "started_at": "2026-09-24T21:13:00Z",
        "ended_at": "2026-09-24T21:54:00Z",
        "exercises": [
            {
                "exercise_id": exercise_id,
                "superset_group": None,
                "sets": [
                    {"set_type": "normal", "weight_kg": 40, "reps": 10},
                    {"set_type": "dropset", "weight_kg": 30, "reps": 12},
                ],
            }
        ],
    }
    response = await client.post("/activities", json=payload)
    assert response.status_code == 201
    body = response.json()
    assert body["title"] == "Evening workout"
    assert len(body["exercises"][0]["sets"]) == 2
    assert body["exercises"][0]["sets"][1]["set_type"] == "dropset"


async def test_list_activities_filters_by_date_range(client: AsyncClient) -> None:
    exercise_id = await _create_exercise(client)
    for day in ("2026-01-01", "2026-06-01", "2026-12-01"):
        await client.post(
            "/activities",
            json={
                "title": f"Session {day}",
                "started_at": f"{day}T10:00:00Z",
                "exercises": [{"exercise_id": exercise_id, "sets": []}],
            },
        )

    response = await client.get(
        "/activities", params={"since": "2026-02-01T00:00:00Z", "until": "2026-11-01T00:00:00Z"}
    )
    assert response.status_code == 200
    titles = [item["title"] for item in response.json()]
    assert titles == ["Session 2026-06-01"]


async def test_get_missing_activity_is_404(client: AsyncClient) -> None:
    response = await client.get("/activities/999")
    assert response.status_code == 404


async def test_create_activity_referencing_own_routine(client: AsyncClient) -> None:
    exercise_id = await _create_exercise(client)
    routine = await client.post(
        "/routines",
        json={"name": "Push day", "exercises": [{"exercise_id": exercise_id, "sets": []}]},
    )
    routine_id = routine.json()["id"]

    response = await client.post(
        "/activities",
        json={
            "title": "Ran the routine",
            "started_at": "2026-01-01T10:00:00Z",
            "routine_id": routine_id,
            "exercises": [],
        },
    )
    assert response.status_code == 201
    assert response.json()["routine_id"] == routine_id


async def test_replace_activity(client: AsyncClient) -> None:
    exercise_id = await _create_exercise(client)
    created = await client.post(
        "/activities",
        json={
            "title": "Original",
            "started_at": "2026-01-01T10:00:00Z",
            "exercises": [{"exercise_id": exercise_id, "sets": []}],
        },
    )
    activity_id = created.json()["id"]

    response = await client.put(
        f"/activities/{activity_id}",
        json={
            "title": "Replaced",
            "started_at": "2026-01-01T11:00:00Z",
            "exercises": [{"exercise_id": exercise_id, "sets": [{"reps": 5, "weight_kg": 50}]}],
        },
    )
    assert response.status_code == 200
    assert response.json()["title"] == "Replaced"
    assert len(response.json()["exercises"][0]["sets"]) == 1


async def test_replace_missing_activity_is_404(client: AsyncClient) -> None:
    response = await client.put(
        "/activities/999",
        json={"title": "x", "started_at": "2026-01-01T10:00:00Z", "exercises": []},
    )
    assert response.status_code == 404


async def test_delete_activity(client: AsyncClient) -> None:
    created = await client.post(
        "/activities",
        json={"title": "To delete", "started_at": "2026-01-01T10:00:00Z", "exercises": []},
    )
    activity_id = created.json()["id"]

    response = await client.delete(f"/activities/{activity_id}")
    assert response.status_code == 204

    response = await client.get(f"/activities/{activity_id}")
    assert response.status_code == 404


async def test_delete_missing_activity_is_404(client: AsyncClient) -> None:
    response = await client.delete("/activities/999")
    assert response.status_code == 404


async def test_replayed_create_returns_the_existing_activity(client: AsyncClient) -> None:
    """A live workout retried after a lost response must not be saved twice."""
    exercise_id = await _create_exercise(client)
    payload = {
        "title": "Evening workout",
        "started_at": "2026-09-24T21:13:00.123456Z",
        "ended_at": "2026-09-24T21:54:00Z",
        "exercises": [{"exercise_id": exercise_id, "sets": [{"weight_kg": 40, "reps": 10}]}],
    }

    first = await client.post("/activities", json=payload)
    replay = await client.post("/activities", json=payload)

    assert first.status_code == 201
    assert replay.status_code == 200
    assert replay.json()["id"] == first.json()["id"]
    assert replay.json()["exercises"] == first.json()["exercises"]
    assert len((await client.get("/activities")).json()) == 1


async def test_creates_differing_in_title_or_start_are_not_replays(client: AsyncClient) -> None:
    exercise_id = await _create_exercise(client)
    base = {
        "title": "Workout",
        "started_at": "2026-09-24T21:13:00Z",
        "exercises": [{"exercise_id": exercise_id, "sets": []}],
    }
    await client.post("/activities", json=base)

    other_title = await client.post("/activities", json={**base, "title": "Other"})
    other_start = await client.post(
        "/activities", json={**base, "started_at": "2026-09-25T21:13:00Z"}
    )

    assert other_title.status_code == 201
    assert other_start.status_code == 201
    assert len((await client.get("/activities")).json()) == 3
