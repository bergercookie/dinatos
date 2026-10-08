"""Shared test data for the backup / user-export roundtrip tests: a small but
realistic multi-user server, built through the public API wherever there is
one (so the roundtrip is checked against what the app actually produces).
"""

from dataclasses import dataclass
from typing import Any

from httpx2 import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from dinatos_backend.models.activity import Activity
from dinatos_backend.models.hevy_import import HevyImportKind, HevyImportRecord
from dinatos_backend.models.intervals_import import IntervalsImportedActivity

PASSWORD = "hunter22"


@dataclass
class Account:
    email: str
    headers: dict[str, str]


async def login(client: AsyncClient, email: str, password: str = PASSWORD) -> Account:
    response = await client.post(
        "/auth/login", json={"email": email, "password": password}, headers={"Authorization": ""}
    )
    assert response.status_code == 200, response.text
    return Account(email, {"Authorization": f"Bearer {response.json()['access_token']}"})


async def register(client: AsyncClient, email: str) -> Account:
    # `headers={"Authorization": ""}` stops the fixture's default admin token
    # from being sent; registration needs none.
    response = await client.post(
        "/auth/register",
        json={"email": email, "password": PASSWORD},
        headers={"Authorization": ""},
    )
    assert response.status_code == 201, response.text
    return await login(client, email)


async def create_exercise(client: AsyncClient, account: Account, name: str, **fields: Any) -> int:
    response = await client.post(
        "/exercises", json={"name": name, **fields}, headers=account.headers
    )
    assert response.status_code == 201, response.text
    exercise_id: int = response.json()["id"]
    return exercise_id


async def post(client: AsyncClient, account: Account, path: str, body: dict[str, Any]) -> Any:
    response = await client.post(path, json=body, headers=account.headers)
    assert response.status_code == 201, response.text
    return response.json()


@dataclass
class Seeded:
    admin: Account
    alice: Account
    bob: Account


async def populate(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]
) -> Seeded:
    """`client` is the fixture's pre-registered first user (an admin), here
    `test@example.com`. Adds two more accounts and a spread of data for all three.
    """
    admin = await login(client, "test@example.com")
    alice = await register(client, "alice@example.com")
    bob = await register(client, "bob@example.com")

    bench = await create_exercise(
        client,
        admin,
        "Bench Press",
        equipment="barbell",
        primary_muscles=["chest"],
        secondary_muscles=["triceps", "shoulders"],
    )
    run = await create_exercise(
        client,
        alice,
        "Hill Sprint",
        tracks_weight=False,
        tracks_reps=False,
        tracks_distance=True,
        tracks_duration=True,
    )
    curl = await create_exercise(client, bob, "Bob's Curl", primary_muscles=["biceps"])

    push = await post(
        client,
        alice,
        "/routines",
        {
            "name": "Push",
            "description": "Chest day",
            "exercises": [
                {
                    "exercise_id": bench,
                    "superset_group": 1,
                    "notes": "pause on chest",
                    "sets": [
                        {"set_type": "warmup", "target_weight_kg": 40, "target_reps": 10},
                        {"set_type": "normal", "target_weight_kg": 80.5, "target_reps": 5},
                    ],
                },
                {
                    "exercise_id": run,
                    "superset_group": 1,
                    "sets": [{"target_distance_km": 0.2}],
                },
            ],
        },
    )
    await post(client, alice, "/routines", {"name": "Empty", "exercises": []})
    await post(
        client,
        bob,
        "/routines",
        {"name": "Arms", "exercises": [{"exercise_id": curl, "sets": [{"target_reps": 12}]}]},
    )
    await post(
        client,
        admin,
        "/routines",
        {"name": "Admin bench", "exercises": [{"exercise_id": bench, "sets": []}]},
    )

    await post(
        client,
        alice,
        "/activities",
        {
            "title": "Monday push",
            "description": "felt strong",
            "started_at": "2026-01-05T08:00:00Z",
            "ended_at": "2026-01-05T09:10:00Z",
            "routine_id": push["id"],
            "exercises": [
                {
                    "exercise_id": bench,
                    "superset_group": 1,
                    "notes": "PR",
                    "sets": [
                        {"weight_kg": 82.5, "reps": 5},
                        {"set_type": "dropset", "weight_kg": 60, "reps": 8},
                    ],
                },
                {"exercise_id": run, "sets": [{"distance_km": 0.2, "duration_seconds": 41}]},
            ],
        },
    )
    await post(
        client,
        alice,
        "/activities",
        {"title": "Ad hoc", "started_at": "2026-01-07T18:30:00+02:00", "exercises": []},
    )
    await post(
        client,
        bob,
        "/activities",
        {
            "title": "Bob's curls",
            "started_at": "2026-01-06T07:00:00Z",
            "exercises": [{"exercise_id": curl, "sets": [{"weight_kg": 15, "reps": 10}]}],
        },
    )

    await post(
        client,
        alice,
        "/measurements",
        {"measured_at": "2026-01-01T07:00:00Z", "weight_kg": 71.2, "waist_cm": 80},
    )
    await post(
        client,
        alice,
        "/measurements",
        {
            "measured_at": "2026-02-01T07:00:00Z",
            "weight_kg": 70.4,
            "fat_percent": 14.5,
            # A smart-scale weigh-in, so the round-trips cover those columns too.
            "muscle_mass_kg": 55.1,
            "metabolic_age": 27,
            "dci_kcal": 2410,
            "right_arm_muscle_kg": 3.2,
            "trunk_fat_percent": 16.3,
        },
    )
    await post(
        client, bob, "/measurements", {"measured_at": "2026-01-02T07:00:00Z", "weight_kg": 90}
    )

    for account, height, units, key in (
        (alice, 171.5, "imperial", "alice-secret-key"),
        (bob, 190, "metric", None),
    ):
        response = await client.patch(
            "/profile",
            json={"height_cm": height, "unit_system": units, "workoutx_api_key": key},
            headers=account.headers,
        )
        assert response.status_code == 200

    async with session_factory() as session:
        alice_id = (await client.get("/auth/me", headers=alice.headers)).json()["id"]
        session.add(
            HevyImportRecord(
                owner_id=alice_id,
                kind=HevyImportKind.workouts,
                content_hash="a" * 64,
                filename="workout_data.csv",
                activities_created=3,
                exercises_created=2,
            )
        )
        ad_hoc = await session.scalar(
            select(Activity).where(Activity.owner_id == alice_id, Activity.title == "Ad hoc")
        )
        assert ad_hoc is not None
        session.add(
            IntervalsImportedActivity(
                owner_id=alice_id,
                intervals_id="i123",
                activity_id=ad_hoc.id,
                started_at=ad_hoc.started_at,
            )
        )
        await session.commit()
    return Seeded(admin, alice, bob)
