from collections.abc import Callable

import httpx2 as httpx
from httpx2 import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.api.deps import get_tutorial_provider_for_user, get_workoutx_provider_for_user
from dinatos_backend.main import app
from dinatos_backend.models.exercise import Exercise
from dinatos_backend.services.tutorials import ExerciseTutorial
from dinatos_backend.services.tutorials.workoutx import WorkoutXProvider


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
    assert body["is_custom"] is True

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


async def test_list_exercises_filters_by_built_in_or_custom(
    client: AsyncClient, db: AsyncSession
) -> None:
    db.add(Exercise(name="Squat (Barbell)", is_custom=False))
    await db.commit()
    await client.post("/exercises", json={"name": "My Own Lift"})

    custom = await client.get("/exercises", params={"is_custom": "true"})
    assert [item["name"] for item in custom.json()] == ["My Own Lift"]
    assert custom.headers["X-Total-Count"] == "1"

    built_in = await client.get("/exercises", params={"is_custom": "false"})
    assert [item["name"] for item in built_in.json()] == ["Squat (Barbell)"]

    both = await client.get("/exercises")
    assert [item["name"] for item in both.json()] == ["My Own Lift", "Squat (Barbell)"]


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


async def test_builtin_exercise_cannot_be_updated(client: AsyncClient, db: AsyncSession) -> None:
    exercise = Exercise(name="Squat (Barbell)", is_custom=False)
    db.add(exercise)
    await db.commit()

    response = await client.patch(f"/exercises/{exercise.id}", json={"tracks_duration": True})

    assert response.status_code == 403
    response = await client.get(f"/exercises/{exercise.id}")
    assert response.json()["tracks_duration"] is False


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


async def test_builtin_exercise_cannot_be_deleted(client: AsyncClient, db: AsyncSession) -> None:
    exercise = Exercise(name="Squat (Barbell)", is_custom=False)
    db.add(exercise)
    await db.commit()

    response = await client.delete(f"/exercises/{exercise.id}")

    assert response.status_code == 403
    response = await client.get(f"/exercises/{exercise.id}")
    assert response.status_code == 200


async def test_delete_missing_exercise_is_404(client: AsyncClient) -> None:
    response = await client.delete("/exercises/999")
    assert response.status_code == 404


async def test_create_exercise_with_equipment_and_muscles(client: AsyncClient) -> None:
    response = await client.post(
        "/exercises",
        json={
            "name": "Cable Fly",
            "equipment": "cable",
            "primary_muscles": ["chest"],
            "secondary_muscles": ["shoulders", "triceps"],
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["equipment"] == "cable"
    assert body["primary_muscles"] == ["chest"]
    assert set(body["secondary_muscles"]) == {"shoulders", "triceps"}

    response = await client.get(f"/exercises/{body['id']}")
    assert response.json()["equipment"] == "cable"


async def test_create_exercise_without_equipment_or_muscles_defaults_to_empty(
    client: AsyncClient,
) -> None:
    response = await client.post("/exercises", json={"name": "Squat (Barbell)"})

    assert response.status_code == 201
    body = response.json()
    assert body["equipment"] is None
    assert body["primary_muscles"] == []
    assert body["secondary_muscles"] == []


async def test_create_exercise_a_muscle_listed_as_both_counts_as_primary(
    client: AsyncClient,
) -> None:
    """The same muscle can't be stored as both primary and secondary (see
    `ExerciseMuscle`'s unique constraint) -- primary wins on overlap.
    """
    response = await client.post(
        "/exercises",
        json={
            "name": "Clean and Press",
            "primary_muscles": ["shoulders"],
            "secondary_muscles": ["shoulders", "triceps"],
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["primary_muscles"] == ["shoulders"]
    assert body["secondary_muscles"] == ["triceps"]


async def test_update_exercise_muscles(client: AsyncClient) -> None:
    created = await client.post(
        "/exercises", json={"name": "Squat (Barbell)", "primary_muscles": ["quadriceps"]}
    )
    exercise_id = created.json()["id"]

    response = await client.patch(
        f"/exercises/{exercise_id}",
        json={"equipment": "barbell", "secondary_muscles": ["glutes"]},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["equipment"] == "barbell"
    # primary_muscles wasn't mentioned in this update, so it's unchanged.
    assert body["primary_muscles"] == ["quadriceps"]
    assert body["secondary_muscles"] == ["glutes"]


async def test_update_exercise_can_clear_equipment(client: AsyncClient) -> None:
    created = await client.post(
        "/exercises", json={"name": "Deadlift (Barbell)", "equipment": "barbell"}
    )
    exercise_id = created.json()["id"]

    response = await client.patch(f"/exercises/{exercise_id}", json={"equipment": None})

    assert response.status_code == 200
    assert response.json()["equipment"] is None


async def test_list_exercises_filters_by_equipment(client: AsyncClient) -> None:
    await client.post("/exercises", json={"name": "Squat (Barbell)", "equipment": "barbell"})
    await client.post("/exercises", json={"name": "Squat (Dumbbell)", "equipment": "dumbbell"})

    response = await client.get("/exercises", params={"equipment": "barbell"})

    assert response.status_code == 200
    names = [item["name"] for item in response.json()]
    assert names == ["Squat (Barbell)"]


async def test_list_exercises_filters_by_muscle_matching_either_primary_or_secondary(
    client: AsyncClient,
) -> None:
    await client.post(
        "/exercises", json={"name": "Squat (Barbell)", "primary_muscles": ["quadriceps"]}
    )
    await client.post("/exercises", json={"name": "Leg Press", "secondary_muscles": ["quadriceps"]})
    await client.post("/exercises", json={"name": "Bench Press", "primary_muscles": ["chest"]})

    response = await client.get("/exercises", params={"muscle": "quadriceps"})

    assert response.status_code == 200
    names = {item["name"] for item in response.json()}
    assert names == {"Squat (Barbell)", "Leg Press"}


async def test_exercise_records_reflects_the_callers_best_sets(client: AsyncClient) -> None:
    exercise_id = (await client.post("/exercises", json={"name": "Squat (Barbell)"})).json()["id"]

    response = await client.get(f"/exercises/{exercise_id}/records")
    assert response.status_code == 200
    assert response.json() == {"max_weight_kg": None, "max_reps": None}

    await client.post(
        "/activities",
        json={
            "title": "Session 1",
            "started_at": "2026-09-01T10:00:00Z",
            "exercises": [
                {
                    "exercise_id": exercise_id,
                    "sets": [
                        {"weight_kg": 60, "reps": 8},
                        {"weight_kg": 80, "reps": 3},
                    ],
                }
            ],
        },
    )
    await client.post(
        "/activities",
        json={
            "title": "Session 2",
            "started_at": "2026-09-08T10:00:00Z",
            "exercises": [{"exercise_id": exercise_id, "sets": [{"weight_kg": 70, "reps": 10}]}],
        },
    )

    response = await client.get(f"/exercises/{exercise_id}/records")
    assert response.status_code == 200
    assert response.json() == {"max_weight_kg": 80.0, "max_reps": 10}


async def test_exercise_records_is_404_for_a_missing_exercise(client: AsyncClient) -> None:
    response = await client.get("/exercises/999/records")
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
    app.dependency_overrides[get_tutorial_provider_for_user] = lambda: _FakeProvider(
        result=tutorial
    )

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
    app.dependency_overrides[get_tutorial_provider_for_user] = lambda: _FakeProvider(result=None)

    response = await client.get("/exercises/999/tutorial")

    assert response.status_code == 404


async def test_get_exercise_tutorial_is_404_when_the_provider_has_nothing(
    client: AsyncClient,
) -> None:
    created = await client.post("/exercises", json={"name": "A Custom Exercise"})
    exercise_id = created.json()["id"]
    app.dependency_overrides[get_tutorial_provider_for_user] = lambda: _FakeProvider(result=None)

    response = await client.get(f"/exercises/{exercise_id}/tutorial")

    assert response.status_code == 404


async def test_get_exercise_tutorial_is_502_when_the_provider_is_unreachable(
    client: AsyncClient,
) -> None:
    created = await client.post("/exercises", json={"name": "A Custom Exercise"})
    exercise_id = created.json()["id"]
    app.dependency_overrides[get_tutorial_provider_for_user] = lambda: _FakeProvider(
        error=httpx.ConnectError("connection refused")
    )

    response = await client.get(f"/exercises/{exercise_id}/tutorial")

    assert response.status_code == 502


async def test_get_exercise_tutorial_502_still_carries_cors_headers(client: AsyncClient) -> None:
    """Deliberately a plain `KeyError`, not `httpx2.HTTPError`: a
    third-party provider's response shape is never fully trusted, and the
    router has to turn *any* failure into a real `HTTPException` --
    letting one through unhandled bypasses `CORSMiddleware` entirely
    (it sits *outside* `ServerErrorMiddleware`'s reach), so the browser
    sees a bare, unheadered 500 and reports a misleading "CORS header
    missing" instead of the real error.
    """
    created = await client.post("/exercises", json={"name": "A Custom Exercise"})
    exercise_id = created.json()["id"]
    app.dependency_overrides[get_tutorial_provider_for_user] = lambda: _FakeProvider(
        error=KeyError("gifUrl")
    )

    response = await client.get(
        f"/exercises/{exercise_id}/tutorial", headers={"Origin": "http://127.0.0.1:8081"}
    )

    assert response.status_code == 502
    assert response.headers["access-control-allow-origin"] == "*"


def _workoutx_gif_provider(handler: Callable[[httpx.Request], httpx.Response]) -> WorkoutXProvider:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url="https://api.workoutxapp.com/v1"
    )
    return WorkoutXProvider("wx_test", client=client)


async def test_workoutx_gif_is_proxied_with_the_users_key(client: AsyncClient) -> None:
    seen: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["path"] = request.url.path
        seen["key"] = request.headers["x-workoutx-key"]
        return httpx.Response(200, content=b"GIF89a", headers={"content-type": "image/gif"})

    provider = _workoutx_gif_provider(handler)
    app.dependency_overrides[get_workoutx_provider_for_user] = lambda: provider

    response = await client.get("/exercises/media/workoutx/0025.gif")

    assert response.status_code == 200
    assert response.content == b"GIF89a"
    assert response.headers["content-type"] == "image/gif"
    assert seen == {"path": "/v1/gifs/0025.gif", "key": "wx_test"}


async def test_workoutx_gif_is_502_when_upstream_rejects_the_key(client: AsyncClient) -> None:
    provider = _workoutx_gif_provider(lambda _request: httpx.Response(401, json={}))
    app.dependency_overrides[get_workoutx_provider_for_user] = lambda: provider

    response = await client.get("/exercises/media/workoutx/0025.gif")

    assert response.status_code == 502


async def test_workoutx_gif_is_404_without_a_saved_key(client: AsyncClient) -> None:
    response = await client.get("/exercises/media/workoutx/0025.gif")

    assert response.status_code == 404


async def test_workoutx_gif_requires_auth(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.get("/exercises/media/workoutx/0025.gif")

    assert response.status_code in (401, 403)


async def test_workoutx_gif_rejects_a_malformed_id(client: AsyncClient) -> None:
    provider = _workoutx_gif_provider(lambda _request: httpx.Response(200, content=b"x"))
    app.dependency_overrides[get_workoutx_provider_for_user] = lambda: provider

    response = await client.get("/exercises/media/workoutx/a.b.gif")

    assert response.status_code == 404


async def test_exercise_records_ignore_warmup_sets(client: AsyncClient) -> None:
    exercise_id = (await client.post("/exercises", json={"name": "Squat (Barbell)"})).json()["id"]
    await client.post(
        "/activities",
        json={
            "title": "Session",
            "started_at": "2026-09-01T10:00:00Z",
            "exercises": [
                {
                    "exercise_id": exercise_id,
                    "sets": [
                        {"set_type": "warmup", "weight_kg": 200, "reps": 30},
                        {"set_type": "normal", "weight_kg": 60, "reps": 8},
                    ],
                }
            ],
        },
    )

    response = await client.get(f"/exercises/{exercise_id}/records")
    assert response.json() == {"max_weight_kg": 60.0, "max_reps": 8}


async def test_exercise_history_lists_own_sessions_newest_first(client: AsyncClient) -> None:
    exercise_id = (await client.post("/exercises", json={"name": "Squat (Barbell)"})).json()["id"]
    other_id = (await client.post("/exercises", json={"name": "Leg Press"})).json()["id"]
    assert (await client.get(f"/exercises/{exercise_id}/history")).json() == []

    for day, weight in (("01", 60), ("08", 65), ("15", 70)):
        await client.post(
            "/activities",
            json={
                "title": f"Session {day}",
                "started_at": f"2026-09-{day}T10:00:00Z",
                "exercises": [
                    {"exercise_id": exercise_id, "sets": [{"weight_kg": weight, "reps": 5}]},
                    {"exercise_id": other_id, "sets": [{"weight_kg": 999, "reps": 1}]},
                ],
            },
        )

    response = await client.get(f"/exercises/{exercise_id}/history", params={"limit": 2})
    assert response.status_code == 200
    body = response.json()
    assert [entry["activity_title"] for entry in body] == ["Session 15", "Session 08"]
    assert body[0]["sets"] == [
        {
            "set_type": "normal",
            "weight_kg": 70.0,
            "reps": 5,
            "distance_km": None,
            "duration_seconds": None,
        }
    ]


async def test_exercise_history_merges_an_exercise_logged_twice_in_one_activity(
    client: AsyncClient,
) -> None:
    exercise_id = (await client.post("/exercises", json={"name": "Curl"})).json()["id"]
    await client.post(
        "/activities",
        json={
            "title": "Arms",
            "started_at": "2026-09-01T10:00:00Z",
            "exercises": [
                {"exercise_id": exercise_id, "sets": [{"weight_kg": 10, "reps": 10}]},
                {"exercise_id": exercise_id, "sets": [{"weight_kg": 12, "reps": 8}]},
            ],
        },
    )

    body = (await client.get(f"/exercises/{exercise_id}/history")).json()
    assert len(body) == 1
    assert [s["weight_kg"] for s in body[0]["sets"]] == [10.0, 12.0]


async def test_exercise_history_is_404_for_a_missing_exercise(client: AsyncClient) -> None:
    assert (await client.get("/exercises/999/history")).status_code == 404


async def test_only_completed_sets_count_for_records_and_history(client: AsyncClient) -> None:
    exercise_id = (await client.post("/exercises", json={"name": "Squat (Barbell)"})).json()["id"]
    created = await client.post(
        "/activities",
        json={
            "title": "Session",
            "started_at": "2026-09-01T10:00:00Z",
            "exercises": [
                {
                    "exercise_id": exercise_id,
                    "sets": [
                        {"weight_kg": 60, "reps": 8},  # completed unless it says otherwise
                        {"weight_kg": 200, "reps": 30, "completed": False},
                    ],
                }
            ],
        },
    )
    sets = created.json()["exercises"][0]["sets"]
    assert [s["completed"] for s in sets] == [True, False]

    records = await client.get(f"/exercises/{exercise_id}/records")
    assert records.json() == {"max_weight_kg": 60.0, "max_reps": 8}
    history = (await client.get(f"/exercises/{exercise_id}/history")).json()
    assert [s["weight_kg"] for s in history[0]["sets"]] == [60.0]

    # A session with nothing ticked off is not a session of the exercise yet.
    await client.post(
        "/activities",
        json={
            "title": "Planned only",
            "started_at": "2026-09-02T10:00:00Z",
            "exercises": [
                {
                    "exercise_id": exercise_id,
                    "sets": [{"weight_kg": 100, "reps": 5, "completed": False}],
                }
            ],
        },
    )
    history = (await client.get(f"/exercises/{exercise_id}/history")).json()
    assert [entry["activity_title"] for entry in history] == ["Session"]
