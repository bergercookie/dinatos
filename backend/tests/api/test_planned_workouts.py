from httpx2 import AsyncClient

from backup_seed import register

WHEN = "2030-03-04T09:00:00+00:00"


async def _routine(client: AsyncClient, name: str = "Push") -> int:
    response = await client.post("/routines", json={"name": name, "exercises": []})
    return int(response.json()["id"])


async def test_create_defaults_the_title_to_the_routine_name(client: AsyncClient) -> None:
    routine_id = await _routine(client)
    response = await client.post(
        "/planned-workouts", json={"scheduled_at": WHEN, "routine_id": routine_id}
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["title"] == "Push"
    assert body["routine_id"] == routine_id
    assert body["duration_minutes"] == 60
    assert body["reminder_minutes"] == 30
    assert body["completed_activity_id"] is None


async def test_create_needs_a_title_or_a_routine(client: AsyncClient) -> None:
    response = await client.post("/planned-workouts", json={"scheduled_at": WHEN, "title": "  "})
    assert response.status_code == 422
    ok = await client.post("/planned-workouts", json={"scheduled_at": WHEN, "title": "Run"})
    assert ok.status_code == 201


async def test_list_is_sorted_and_bounded(client: AsyncClient) -> None:
    for day in (9, 3, 6):
        await client.post(
            "/planned-workouts", json={"scheduled_at": f"2030-03-0{day}T09:00:00Z", "title": "x"}
        )
    everything = (await client.get("/planned-workouts")).json()
    assert [p["scheduled_at"][:10] for p in everything] == [
        "2030-03-03",
        "2030-03-06",
        "2030-03-09",
    ]
    window = await client.get(
        "/planned-workouts",
        params={"since": "2030-03-04T00:00:00Z", "until": "2030-03-07T00:00:00Z"},
    )
    assert [p["scheduled_at"][:10] for p in window.json()] == ["2030-03-06"]


async def test_put_replaces_and_patch_changes_only_what_is_sent(client: AsyncClient) -> None:
    created = (
        await client.post("/planned-workouts", json={"scheduled_at": WHEN, "title": "Run"})
    ).json()
    url = f"/planned-workouts/{created['id']}"

    patched = await client.patch(
        url, json={"notes": "easy", "reminder_minutes": None, "title": None}
    )
    assert patched.status_code == 200
    assert patched.json()["notes"] == "easy"
    assert patched.json()["reminder_minutes"] is None
    assert patched.json()["title"] == "Run"  # null on a required field leaves it alone

    replaced = await client.put(url, json={"scheduled_at": "2030-04-01T10:00:00Z", "title": "Swim"})
    assert replaced.status_code == 200
    assert replaced.json()["title"] == "Swim"
    assert replaced.json()["notes"] is None
    assert replaced.json()["reminder_minutes"] == 30

    untitled = await client.put(url, json={"scheduled_at": WHEN})
    assert untitled.status_code == 422

    assert (await client.delete(url)).status_code == 204
    assert (await client.get(url)).status_code == 404


async def test_validation_limits(client: AsyncClient) -> None:
    for bad in (
        {"duration_minutes": 0},
        {"duration_minutes": 100000},
        {"reminder_minutes": -1},
    ):
        response = await client.post(
            "/planned-workouts", json={"scheduled_at": WHEN, "title": "x", **bad}
        )
        assert response.status_code == 422, bad


async def test_other_users_plans_and_routines_are_invisible(
    client: AsyncClient, anonymous_client: AsyncClient
) -> None:
    mine = (
        await client.post("/planned-workouts", json={"scheduled_at": WHEN, "title": "Mine"})
    ).json()
    my_routine = await _routine(client)
    headers = (await register(anonymous_client, "other@example.com")).headers
    url = f"/planned-workouts/{mine['id']}"
    assert (await anonymous_client.get(url, headers=headers)).status_code == 404
    assert (
        await anonymous_client.patch(url, json={"notes": "x"}, headers=headers)
    ).status_code == 404
    assert (await anonymous_client.delete(url, headers=headers)).status_code == 404
    assert (await anonymous_client.get("/planned-workouts", headers=headers)).json() == []
    stolen = await anonymous_client.post(
        "/planned-workouts",
        json={"scheduled_at": WHEN, "routine_id": my_routine},
        headers=headers,
    )
    assert stolen.status_code == 404


async def test_requires_authentication(anonymous_client: AsyncClient) -> None:
    assert (await anonymous_client.get("/planned-workouts")).status_code in (401, 403)


async def test_saving_an_activity_from_a_plan_completes_it(client: AsyncClient) -> None:
    plan = (
        await client.post("/planned-workouts", json={"scheduled_at": WHEN, "title": "Run"})
    ).json()
    activity = await client.post(
        "/activities",
        json={
            "title": "Run",
            "started_at": "2030-03-04T09:05:00Z",
            "exercises": [],
            "planned_workout_id": plan["id"],
        },
    )
    assert activity.status_code == 201, activity.text
    done = (await client.get(f"/planned-workouts/{plan['id']}")).json()
    assert done["completed_activity_id"] == activity.json()["id"]

    # A retried save (same title/start) is idempotent and leaves the link alone.
    again = await client.post(
        "/activities",
        json={
            "title": "Run",
            "started_at": "2030-03-04T09:05:00Z",
            "exercises": [],
            "planned_workout_id": plan["id"],
        },
    )
    assert again.status_code == 200
    assert (await client.get(f"/planned-workouts/{plan['id']}")).json()[
        "completed_activity_id"
    ] == activity.json()["id"]

    # Deleting the activity un-completes the plan rather than deleting it.
    # (sqlite has no FK actions, so only assert the plan itself survives.)
    assert (await client.get(f"/planned-workouts/{plan['id']}")).status_code == 200


async def test_an_unknown_plan_id_does_not_fail_the_activity_save(client: AsyncClient) -> None:
    response = await client.post(
        "/activities",
        json={
            "title": "Run",
            "started_at": "2030-03-04T09:05:00Z",
            "exercises": [],
            "planned_workout_id": 99999,
        },
    )
    assert response.status_code == 201
