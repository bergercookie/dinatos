import httpx
from httpx import AsyncClient

from dinatos_backend.main import app
from dinatos_backend.services.tutorials import ExerciseTutorial, get_tutorial_provider


class _FakeProvider:
    def __init__(
        self, result: ExerciseTutorial | None = None, error: Exception | None = None
    ) -> None:
        self._result = result
        self._error = error

    async def get_tutorial(self, _exercise_name: str) -> ExerciseTutorial | None:
        if self._error is not None:
            raise self._error
        return self._result


async def test_create_and_get_exercise(client: AsyncClient) -> None:
    response = await client.post("/exercises", json={"name": "Squat (Barbell)"})
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Squat (Barbell)"
    assert body["tracks_weight"] is True
    assert body["tracks_distance"] is False

    response = await client.get(f"/exercises/{body['id']}")
    assert response.status_code == 200
    assert response.json()["name"] == "Squat (Barbell)"


async def test_get_missing_exercise_is_404(client: AsyncClient) -> None:
    response = await client.get("/exercises/999")
    assert response.status_code == 404


async def test_list_exercises_filters_by_search(client: AsyncClient) -> None:
    await client.post("/exercises", json={"name": "Squat (Barbell)"})
    await client.post("/exercises", json={"name": "Bench Press (Dumbbell)"})

    response = await client.get("/exercises", params={"search": "squat"})
    assert response.status_code == 200
    names = [item["name"] for item in response.json()]
    assert names == ["Squat (Barbell)"]

    response = await client.get("/exercises")
    assert response.status_code == 200
    names = [item["name"] for item in response.json()]
    assert names == ["Bench Press (Dumbbell)", "Squat (Barbell)"]


async def test_list_exercises_without_limit_returns_everything(client: AsyncClient) -> None:
    for name in ["Squat (Barbell)", "Bench Press (Dumbbell)", "Deadlift (Barbell)"]:
        await client.post("/exercises", json={"name": name})

    response = await client.get("/exercises")

    assert response.status_code == 200
    assert response.headers["x-total-count"] == "3"
    assert len(response.json()) == 3


async def test_list_exercises_paginates_when_limit_is_given(client: AsyncClient) -> None:
    for name in ["Squat (Barbell)", "Bench Press (Dumbbell)", "Deadlift (Barbell)"]:
        await client.post("/exercises", json={"name": name})

    response = await client.get("/exercises", params={"limit": 2})
    assert response.status_code == 200
    assert response.headers["x-total-count"] == "3"
    names = [item["name"] for item in response.json()]
    assert names == ["Bench Press (Dumbbell)", "Deadlift (Barbell)"]

    response = await client.get("/exercises", params={"limit": 2, "offset": 2})
    assert response.status_code == 200
    assert response.headers["x-total-count"] == "3"
    names = [item["name"] for item in response.json()]
    assert names == ["Squat (Barbell)"]


async def test_list_exercises_pagination_respects_search(client: AsyncClient) -> None:
    await client.post("/exercises", json={"name": "Squat (Barbell)"})
    await client.post("/exercises", json={"name": "Squat (Dumbbell)"})
    await client.post("/exercises", json={"name": "Bench Press (Dumbbell)"})

    response = await client.get("/exercises", params={"search": "squat", "limit": 1})

    assert response.status_code == 200
    assert response.headers["x-total-count"] == "2"
    assert len(response.json()) == 1


async def test_list_exercises_rejects_an_out_of_range_limit(client: AsyncClient) -> None:
    response = await client.get("/exercises", params={"limit": 500})
    assert response.status_code == 422


async def test_update_exercise(client: AsyncClient) -> None:
    created = await client.post("/exercises", json={"name": "Plank"})
    exercise_id = created.json()["id"]

    response = await client.patch(f"/exercises/{exercise_id}", json={"tracks_duration": True})
    assert response.status_code == 200
    assert response.json()["tracks_duration"] is True
    assert response.json()["name"] == "Plank"


async def test_update_missing_exercise_is_404(client: AsyncClient) -> None:
    response = await client.patch("/exercises/999", json={"name": "x"})
    assert response.status_code == 404


async def test_delete_exercise(client: AsyncClient) -> None:
    created = await client.post("/exercises", json={"name": "Deadlift (Barbell)"})
    exercise_id = created.json()["id"]

    response = await client.delete(f"/exercises/{exercise_id}")
    assert response.status_code == 204

    response = await client.get(f"/exercises/{exercise_id}")
    assert response.status_code == 404


async def test_delete_missing_exercise_is_404(client: AsyncClient) -> None:
    response = await client.delete("/exercises/999")
    assert response.status_code == 404


async def test_get_exercise_tutorial(client: AsyncClient) -> None:
    created = await client.post("/exercises", json={"name": "Squat (Barbell)"})
    exercise_id = created.json()["id"]
    tutorial = ExerciseTutorial(
        source="fake",
        gif_urls=["https://example.com/a.gif"],
        instructions=["Squat down.", "Stand back up."],
        equipment="barbell",
        primary_muscles=["quadriceps"],
        secondary_muscles=["glutes"],
    )
    app.dependency_overrides[get_tutorial_provider] = lambda: _FakeProvider(result=tutorial)

    response = await client.get(f"/exercises/{exercise_id}/tutorial")

    assert response.status_code == 200
    assert response.json() == {
        "source": "fake",
        "gif_urls": ["https://example.com/a.gif"],
        "instructions": ["Squat down.", "Stand back up."],
        "equipment": "barbell",
        "primary_muscles": ["quadriceps"],
        "secondary_muscles": ["glutes"],
    }


async def test_get_exercise_tutorial_is_404_for_a_missing_exercise(client: AsyncClient) -> None:
    app.dependency_overrides[get_tutorial_provider] = lambda: _FakeProvider(result=None)

    response = await client.get("/exercises/999/tutorial")

    assert response.status_code == 404


async def test_get_exercise_tutorial_is_404_when_the_provider_has_nothing(
    client: AsyncClient,
) -> None:
    created = await client.post("/exercises", json={"name": "A Custom Exercise"})
    exercise_id = created.json()["id"]
    app.dependency_overrides[get_tutorial_provider] = lambda: _FakeProvider(result=None)

    response = await client.get(f"/exercises/{exercise_id}/tutorial")

    assert response.status_code == 404


async def test_get_exercise_tutorial_is_502_when_the_provider_is_unreachable(
    client: AsyncClient,
) -> None:
    created = await client.post("/exercises", json={"name": "A Custom Exercise"})
    exercise_id = created.json()["id"]
    app.dependency_overrides[get_tutorial_provider] = lambda: _FakeProvider(
        error=httpx.ConnectError("connection refused")
    )

    response = await client.get(f"/exercises/{exercise_id}/tutorial")

    assert response.status_code == 502


async def test_get_exercise_tutorial_502_still_carries_cors_headers(client: AsyncClient) -> None:
    """Deliberately a plain `KeyError`, not `httpx.HTTPError`: a
    third-party provider's response shape is never fully trusted, and the
    router has to turn *any* failure into a real `HTTPException` --
    letting one through unhandled bypasses `CORSMiddleware` entirely
    (it sits *outside* `ServerErrorMiddleware`'s reach), so the browser
    sees a bare, unheadered 500 and reports a misleading "CORS header
    missing" instead of the real error.
    """
    created = await client.post("/exercises", json={"name": "A Custom Exercise"})
    exercise_id = created.json()["id"]
    app.dependency_overrides[get_tutorial_provider] = lambda: _FakeProvider(
        error=KeyError("gifUrl")
    )

    response = await client.get(
        f"/exercises/{exercise_id}/tutorial", headers={"Origin": "http://127.0.0.1:8081"}
    )

    assert response.status_code == 502
    assert response.headers["access-control-allow-origin"] == "*"
