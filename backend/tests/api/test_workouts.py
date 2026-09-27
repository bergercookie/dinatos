from httpx import AsyncClient


async def _create_exercise(client: AsyncClient, name: str = "Squat (Barbell)") -> int:
    response = await client.post("/exercises", json={"name": name})
    exercise_id: int = response.json()["id"]
    return exercise_id


async def test_create_workout_with_nested_exercises_and_sets(client: AsyncClient) -> None:
    exercise_id = await _create_exercise(client)

    payload = {
        "name": "Leg day",
        "description": "Squats and lunges",
        "exercises": [
            {
                "exercise_id": exercise_id,
                "notes": "go deep",
                "sets": [
                    {"set_type": "warmup", "target_reps": 10, "target_weight_kg": 20},
                    {"set_type": "normal", "target_reps": 5, "target_weight_kg": 60},
                ],
            }
        ],
    }
    response = await client.post("/workouts", json=payload)
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Leg day"
    assert len(body["exercises"]) == 1
    assert len(body["exercises"][0]["sets"]) == 2
    assert body["exercises"][0]["sets"][0]["set_type"] == "warmup"


async def test_list_and_get_workout(client: AsyncClient) -> None:
    exercise_id = await _create_exercise(client)
    created = await client.post(
        "/workouts",
        json={"name": "Push day", "exercises": [{"exercise_id": exercise_id, "sets": []}]},
    )
    workout_id = created.json()["id"]

    response = await client.get("/workouts")
    assert response.status_code == 200
    assert any(w["id"] == workout_id for w in response.json())

    response = await client.get(f"/workouts/{workout_id}")
    assert response.status_code == 200
    assert response.json()["name"] == "Push day"


async def test_get_missing_workout_is_404(client: AsyncClient) -> None:
    response = await client.get("/workouts/999")
    assert response.status_code == 404


async def test_replace_workout_swaps_exercises(client: AsyncClient) -> None:
    squat_id = await _create_exercise(client, "Squat (Barbell)")
    bench_id = await _create_exercise(client, "Bench Press (Dumbbell)")

    created = await client.post(
        "/workouts",
        json={"name": "Original", "exercises": [{"exercise_id": squat_id, "sets": []}]},
    )
    workout_id = created.json()["id"]

    response = await client.put(
        f"/workouts/{workout_id}",
        json={
            "name": "Replaced",
            "description": "swapped",
            "exercises": [{"exercise_id": bench_id, "sets": [{"target_reps": 8}]}],
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Replaced"
    assert len(body["exercises"]) == 1
    assert body["exercises"][0]["exercise_id"] == bench_id


async def test_replace_missing_workout_is_404(client: AsyncClient) -> None:
    response = await client.put("/workouts/999", json={"name": "x", "exercises": []})
    assert response.status_code == 404


async def test_delete_workout(client: AsyncClient) -> None:
    created = await client.post("/workouts", json={"name": "To delete", "exercises": []})
    workout_id = created.json()["id"]

    response = await client.delete(f"/workouts/{workout_id}")
    assert response.status_code == 204

    response = await client.get(f"/workouts/{workout_id}")
    assert response.status_code == 404


async def test_delete_missing_workout_is_404(client: AsyncClient) -> None:
    response = await client.delete("/workouts/999")
    assert response.status_code == 404
