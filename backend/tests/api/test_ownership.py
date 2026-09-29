"""Cross-user data isolation: one account's workouts/activities/measurements/
profile are invisible to, and untouchable by, any other account.
"""

from httpx2 import AsyncClient


async def _register_and_login(client: AsyncClient, email: str) -> str:
    password = "hunter22"
    await client.post("/auth/register", json={"email": email, "password": password})
    login = await client.post("/auth/login", json={"email": email, "password": password})
    token: str = login.json()["access_token"]
    return token


def _as(client: AsyncClient, token: str) -> AsyncClient:
    client.headers["Authorization"] = f"Bearer {token}"
    return client


async def test_workouts_are_not_visible_to_another_user(anonymous_client: AsyncClient) -> None:
    token_a = await _register_and_login(anonymous_client, "a@example.com")
    token_b = await _register_and_login(anonymous_client, "b@example.com")

    created = await _as(anonymous_client, token_a).post(
        "/workouts", json={"name": "A's routine", "exercises": []}
    )
    workout_id = created.json()["id"]

    as_b = _as(anonymous_client, token_b)
    assert (await as_b.get("/workouts")).json() == []
    assert (await as_b.get(f"/workouts/{workout_id}")).status_code == 404
    assert (
        await as_b.put(f"/workouts/{workout_id}", json={"name": "hijacked", "exercises": []})
    ).status_code == 404
    assert (await as_b.delete(f"/workouts/{workout_id}")).status_code == 404

    # Untouched, from A's own point of view.
    as_a = _as(anonymous_client, token_a)
    assert (await as_a.get(f"/workouts/{workout_id}")).json()["name"] == "A's routine"


async def test_activities_are_not_visible_to_another_user(anonymous_client: AsyncClient) -> None:
    token_a = await _register_and_login(anonymous_client, "a@example.com")
    token_b = await _register_and_login(anonymous_client, "b@example.com")

    created = await _as(anonymous_client, token_a).post(
        "/activities",
        json={"title": "A's session", "started_at": "2026-01-01T10:00:00Z", "exercises": []},
    )
    activity_id = created.json()["id"]

    as_b = _as(anonymous_client, token_b)
    assert (await as_b.get("/activities")).json() == []
    assert (await as_b.get(f"/activities/{activity_id}")).status_code == 404
    assert (await as_b.delete(f"/activities/{activity_id}")).status_code == 404


async def test_an_activity_cannot_reference_another_users_workout(
    anonymous_client: AsyncClient,
) -> None:
    token_a = await _register_and_login(anonymous_client, "a@example.com")
    token_b = await _register_and_login(anonymous_client, "b@example.com")

    workout = await _as(anonymous_client, token_a).post(
        "/workouts", json={"name": "A's routine", "exercises": []}
    )
    workout_id = workout.json()["id"]

    response = await _as(anonymous_client, token_b).post(
        "/activities",
        json={
            "title": "borrowed",
            "started_at": "2026-01-01T10:00:00Z",
            "workout_id": workout_id,
            "exercises": [],
        },
    )
    assert response.status_code == 404


async def test_measurements_are_not_visible_to_another_user(anonymous_client: AsyncClient) -> None:
    token_a = await _register_and_login(anonymous_client, "a@example.com")
    token_b = await _register_and_login(anonymous_client, "b@example.com")

    created = await _as(anonymous_client, token_a).post(
        "/measurements", json={"measured_at": "2026-01-01T00:00:00Z", "weight_kg": 80}
    )
    measurement_id = created.json()["id"]

    as_b = _as(anonymous_client, token_b)
    assert (await as_b.get("/measurements")).json() == []
    assert (await as_b.delete(f"/measurements/{measurement_id}")).status_code == 404


async def test_profiles_are_independent_per_user(anonymous_client: AsyncClient) -> None:
    token_a = await _register_and_login(anonymous_client, "a@example.com")
    token_b = await _register_and_login(anonymous_client, "b@example.com")

    await _as(anonymous_client, token_a).patch("/profile", json={"height_cm": 180})

    profile_b = await _as(anonymous_client, token_b).get("/profile")
    assert profile_b.json()["height_cm"] is None

    profile_a = await _as(anonymous_client, token_a).get("/profile")
    assert profile_a.json()["height_cm"] == 180
