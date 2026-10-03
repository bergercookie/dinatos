from pathlib import Path

from httpx2 import AsyncClient

FIXTURES = Path(__file__).parent.parent / "fixtures"


async def test_import_hevy_workouts_endpoint(client: AsyncClient) -> None:
    csv_bytes = (FIXTURES / "hevy_workouts_sample.csv").read_bytes()

    response = await client.post(
        "/imports/hevy/workouts",
        files={"file": ("workout_data.csv", csv_bytes, "text/csv")},
    )
    assert response.status_code == 200
    body = response.json()
    assert (body["activities_created"], body["exercises_created"]) == (3, 5)
    # Every created exercise is reported, with which fields were guessed.
    assert len(body["created_exercises"]) == 5
    by_name = {e["name"]: e for e in body["created_exercises"]}
    squat = by_name["Squat (Barbell)"]
    assert squat["equipment"] == "barbell"
    assert squat["equipment_guessed"] is True
    assert set(squat) == {
        "id",
        "name",
        "equipment",
        "primary_muscles",
        "secondary_muscles",
        "equipment_guessed",
        "muscles_guessed",
    }

    # The guesses were really saved on the exercise, so the edit screen shows them.
    saved = await client.get(f"/exercises/{squat['id']}")
    assert saved.json()["equipment"] == "barbell"
    assert saved.json()["primary_muscles"] == squat["primary_muscles"]

    activities = await client.get("/activities")
    assert len(activities.json()) == 3


async def test_import_hevy_workouts_endpoint_accepts_pc_export(client: AsyncClient) -> None:
    """The web/PC export writes timestamps in a different format than Android.

    Both must reach the same 200 -- the endpoint does not care which app
    produced the file.
    """
    csv_bytes = (FIXTURES / "hevy_workouts_sample_pc.csv").read_bytes()

    response = await client.post(
        "/imports/hevy/workouts",
        files={"file": ("workout_data.csv", csv_bytes, "text/csv")},
    )
    assert response.status_code == 200
    assert response.json()["exercises_created"] == 5


async def test_reimporting_the_same_workouts_file_is_rejected(client: AsyncClient) -> None:
    csv_bytes = (FIXTURES / "hevy_workouts_sample.csv").read_bytes()
    files = {"file": ("workout_data.csv", csv_bytes, "text/csv")}

    first = await client.post("/imports/hevy/workouts", files=files)
    assert first.status_code == 200

    second = await client.post("/imports/hevy/workouts", files=files)
    assert second.status_code == 409
    assert "already imported" in second.json()["detail"]["message"]
    assert second.json()["detail"]["previous_filename"] == "workout_data.csv"

    # Rejected, so nothing new was actually written.
    activities = await client.get("/activities")
    assert len(activities.json()) == 3


async def test_force_reimports_the_same_workouts_file_anyway(client: AsyncClient) -> None:
    csv_bytes = (FIXTURES / "hevy_workouts_sample.csv").read_bytes()
    files = {"file": ("workout_data.csv", csv_bytes, "text/csv")}

    await client.post("/imports/hevy/workouts", files=files)
    second = await client.post("/imports/hevy/workouts", params={"force": "true"}, files=files)

    assert second.status_code == 200
    # Same activities re-created, but the exercises already exist from the
    # first import -- exercises_created is 0 the second time around.
    assert second.json() == {
        "activities_created": 3,
        "exercises_created": 0,
        "created_exercises": [],
    }

    activities = await client.get("/activities")
    assert len(activities.json()) == 6


async def test_a_different_workouts_file_is_not_treated_as_a_duplicate(client: AsyncClient) -> None:
    csv_bytes = (FIXTURES / "hevy_workouts_sample.csv").read_bytes()
    await client.post(
        "/imports/hevy/workouts", files={"file": ("workout_data.csv", csv_bytes, "text/csv")}
    )

    other_bytes = csv_bytes.replace(b"Leg Day", b"Push Day")
    response = await client.post(
        "/imports/hevy/workouts", files={"file": ("workout_data.csv", other_bytes, "text/csv")}
    )
    assert response.status_code == 200


async def test_import_hevy_measurements_endpoint(client: AsyncClient) -> None:
    csv_bytes = (FIXTURES / "hevy_measurements_sample.csv").read_bytes()

    response = await client.post(
        "/imports/hevy/measurements",
        files={"file": ("measurement_data.csv", csv_bytes, "text/csv")},
    )
    assert response.status_code == 200
    assert response.json() == {"measurements_created": 2}

    measurements = await client.get("/measurements")
    assert len(measurements.json()) == 2


async def test_reimporting_the_same_measurements_file_is_rejected(client: AsyncClient) -> None:
    csv_bytes = (FIXTURES / "hevy_measurements_sample.csv").read_bytes()
    files = {"file": ("measurement_data.csv", csv_bytes, "text/csv")}

    await client.post("/imports/hevy/measurements", files=files)
    second = await client.post("/imports/hevy/measurements", files=files)

    assert second.status_code == 409
    measurements = await client.get("/measurements")
    assert len(measurements.json()) == 2
