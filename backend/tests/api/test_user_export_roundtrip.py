"""A user's own data export and import (`/profile/export`, `/profile/import`):
roundtrip into a fresh account, merge vs replace, and isolation between users.
"""

import json
from typing import Any

import pytest
from httpx2 import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from backup_seed import Account, Seeded, populate, post, register
from dinatos_backend.models.profile import UserProfile


@pytest.fixture
async def seeded(client: AsyncClient, session_factory: async_sessionmaker[AsyncSession]) -> Seeded:
    return await populate(client, session_factory)


async def _export(client: AsyncClient, account: Account) -> dict[str, Any]:
    response = await client.get("/profile/export", headers=account.headers)
    assert response.status_code == 200, response.text
    assert "attachment" in response.headers["content-disposition"]
    document: dict[str, Any] = response.json()
    return document


def _comparable(document: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in document.items() if key != "exported_at"}


async def _import(
    client: AsyncClient, account: Account, document: Any, mode: str | None = None
) -> Any:
    return await client.post(
        "/profile/import",
        params={"mode": mode} if mode else {},
        json=document,
        headers=account.headers,
    )


async def test_export_contains_only_the_callers_data_and_no_secrets(
    client: AsyncClient, seeded: Seeded
) -> None:
    document = await _export(client, seeded.alice)
    text = json.dumps(document)

    assert document["format"] == "dinatos-user-export"
    assert document["format_version"] == 1
    assert document["profile"] == {"height_cm": 171.5, "unit_system": "imperial"}
    assert [r["name"] for r in document["routines"]] == ["Empty", "Push"]
    assert [a["title"] for a in document["activities"]] == ["Monday push", "Ad hoc"]
    assert len(document["measurements"]) == 2
    # Alice's routine uses the admin-created "Bench Press" and her own sprint.
    assert {e["name"] for e in document["exercises"]} == {"Bench Press", "Hill Sprint"}
    assert document["activities"][0]["routine_ref"] == 2  # "Push" is the 2nd routine
    assert document["activities"][1]["routine_ref"] is None

    # Nothing of anyone else's, and nothing secret.
    for forbidden in ("Bob", "Arms", "Admin bench", "alice-secret-key", "argon2", "password", "@"):
        assert forbidden not in text
    assert "id" not in document["routines"][0]
    assert "owner_id" not in text

    bob = await _export(client, seeded.bob)
    assert "Push" not in json.dumps(bob)
    assert [e["name"] for e in bob["exercises"]] == ["Bob's Curl"]


async def test_export_of_an_empty_account(client: AsyncClient) -> None:
    document = (await client.get("/profile/export")).json()
    assert document["routines"] == document["activities"] == document["measurements"] == []
    assert document["exercises"] == []
    assert document["profile"] == {"height_cm": None, "unit_system": "metric"}


async def test_export_then_import_into_a_fresh_account_reproduces_the_data(
    client: AsyncClient, seeded: Seeded
) -> None:
    original = await _export(client, seeded.alice)
    carol = await register(client, "carol@example.com")

    response = await _import(client, carol, original)

    assert response.status_code == 200, response.text
    result = response.json()
    assert result["mode"] == "merge"
    assert result["created"] == {
        "exercises": 0,  # both already exist on this server, matched by name
        "routines": 2,
        "activities": 2,
        "measurements": 2,
        "planned_workouts": 1,
    }
    assert result["skipped"] == {
        "exercises": 0,
        "routines": 0,
        "activities": 0,
        "measurements": 0,
        "planned_workouts": 0,
    }
    assert _comparable(await _export(client, carol)) == _comparable(original)

    # The copy is carol's own: new ids, and independent of alice's data.
    alice_ids = {
        r["id"] for r in (await client.get("/routines", headers=seeded.alice.headers)).json()
    }
    carol_routines = (await client.get("/routines", headers=carol.headers)).json()
    assert len(carol_routines) == 2
    assert not alice_ids & {r["id"] for r in carol_routines}
    activities = (await client.get("/activities", headers=carol.headers)).json()
    push_id = next(r["id"] for r in carol_routines if r["name"] == "Push")
    assert {a["routine_id"] for a in activities} == {push_id, None}
    # ...and alice is untouched.
    assert _comparable(await _export(client, seeded.alice)) == _comparable(original)
    # The API key is not carried over (it was never in the file).
    assert (await client.get("/profile", headers=carol.headers)).json()[
        "has_workoutx_api_key"
    ] is False


async def test_import_creates_missing_exercises_as_custom_and_reuses_existing_ones(
    client: AsyncClient, seeded: Seeded
) -> None:
    document = await _export(client, seeded.alice)
    # Pretend the target server has never heard of "Hill Sprint".
    delete_sprint = await client.get("/exercises", params={"search": "Hill Sprint"})
    sprint_id = delete_sprint.json()[0]["id"]
    for routine in (await client.get("/routines", headers=seeded.alice.headers)).json():
        await client.delete(f"/routines/{routine['id']}", headers=seeded.alice.headers)
    for activity in (await client.get("/activities", headers=seeded.alice.headers)).json():
        await client.delete(f"/activities/{activity['id']}", headers=seeded.alice.headers)
    for plan in (await client.get("/planned-workouts", headers=seeded.alice.headers)).json():
        await client.delete(f"/planned-workouts/{plan['id']}", headers=seeded.alice.headers)
    assert (await client.delete(f"/exercises/{sprint_id}")).status_code == 204

    response = await _import(client, seeded.alice, document)

    assert response.status_code == 200, response.text
    assert response.json()["created"]["exercises"] == 1
    recreated = (await client.get("/exercises", params={"search": "Hill Sprint"})).json()[0]
    assert recreated["is_custom"] is True
    assert recreated["tracks_distance"] is True
    assert recreated["tracks_weight"] is False
    # The existing "Bench Press" was matched, not duplicated or overwritten.
    benches = (await client.get("/exercises", params={"search": "Bench Press"})).json()
    assert len(benches) == 1
    assert benches[0]["primary_muscles"] == ["chest"]
    assert _comparable(await _export(client, seeded.alice)) == _comparable(document)


async def test_merge_is_idempotent_and_keeps_existing_data(
    client: AsyncClient, seeded: Seeded
) -> None:
    document = await _export(client, seeded.alice)
    await post(client, seeded.alice, "/routines", {"name": "Extra, not in file", "exercises": []})

    first = await _import(client, seeded.alice, document)
    second = await _import(client, seeded.alice, document, mode="merge")

    for response in (first, second):
        assert response.status_code == 200, response.text
        assert response.json()["created"] == {
            "exercises": 0,
            "routines": 0,
            "activities": 0,
            "measurements": 0,
            "planned_workouts": 0,
        }
        assert response.json()["skipped"] == {
            "exercises": 0,
            "routines": 2,
            "activities": 2,
            "measurements": 2,
            "planned_workouts": 1,
        }
    names = [
        r["name"] for r in (await client.get("/routines", headers=seeded.alice.headers)).json()
    ]
    assert names == ["Empty", "Extra, not in file", "Push"]
    assert len((await client.get("/activities", headers=seeded.alice.headers)).json()) == 2


async def test_merge_links_imported_activities_to_an_already_present_routine(
    client: AsyncClient, seeded: Seeded
) -> None:
    document = await _export(client, seeded.alice)
    carol = await register(client, "carol@example.com")
    existing = await post(client, carol, "/routines", {"name": "Push", "exercises": []})

    await _import(client, carol, document)

    activities = (await client.get("/activities", headers=carol.headers)).json()
    assert {a["routine_id"] for a in activities} == {existing["id"], None}
    # Only the missing routine was added; the same-named one kept its own content.
    routines = (await client.get("/routines", headers=carol.headers)).json()
    assert [r["name"] for r in routines] == ["Empty", "Push"]
    assert next(r for r in routines if r["name"] == "Push")["exercises"] == []


async def test_same_named_routines_inside_one_file_both_import(
    client: AsyncClient, seeded: Seeded
) -> None:
    document = await _export(client, seeded.bob)
    document["routines"].append({**document["routines"][0], "ref": 2})

    response = await _import(client, seeded.alice, document)

    assert response.json()["created"]["routines"] == 2
    names = [
        r["name"] for r in (await client.get("/routines", headers=seeded.alice.headers)).json()
    ]
    assert names.count("Arms") == 2


async def test_replace_swaps_the_callers_data_for_the_files(
    client: AsyncClient, seeded: Seeded
) -> None:
    alice_before = await _export(client, seeded.alice)
    bob_before = await _export(client, seeded.bob)
    # Local changes that the file does not know about.
    await post(client, seeded.alice, "/routines", {"name": "Local only", "exercises": []})
    await post(client, seeded.alice, "/measurements", {"measured_at": "2030-01-01T00:00:00Z"})

    response = await _import(client, seeded.alice, alice_before, mode="replace")

    assert response.status_code == 200, response.text
    result = response.json()
    assert result["mode"] == "replace"
    assert result["deleted"] == {
        "exercises": 0,
        "routines": 3,
        "activities": 2,
        "measurements": 3,
        "planned_workouts": 1,
    }
    assert result["created"] == {
        "exercises": 0,
        "routines": 2,
        "activities": 2,
        "measurements": 2,
        "planned_workouts": 1,
    }
    assert _comparable(await _export(client, seeded.alice)) == _comparable(alice_before)
    # Only the caller's rows were ever touched.
    assert _comparable(await _export(client, seeded.bob)) == _comparable(bob_before)


async def test_import_applies_settings_but_never_an_api_key(
    client: AsyncClient, session_factory: async_sessionmaker[AsyncSession], seeded: Seeded
) -> None:
    document = await _export(client, seeded.bob)
    document["profile"] = {"height_cm": 160, "unit_system": "imperial"}
    document["profile"]["workoutx_api_key"] = "smuggled"  # unknown field: ignored

    assert (await _import(client, seeded.alice, document)).status_code == 200

    profile = (await client.get("/profile", headers=seeded.alice.headers)).json()
    assert profile["height_cm"] == 160
    assert profile["unit_system"] == "imperial"
    async with session_factory() as session:
        stored = await session.get(UserProfile, 2)  # alice
        assert stored is not None
        assert stored.workoutx_api_key == "alice-secret-key"


async def test_an_import_only_writes_rows_owned_by_the_caller(
    client: AsyncClient, seeded: Seeded
) -> None:
    bob_before = await _export(client, seeded.bob)
    admin_before = await _export(client, seeded.admin)
    document = await _export(client, seeded.alice)

    await _import(client, seeded.alice, document, mode="replace")
    await _import(client, seeded.alice, document)

    assert _comparable(await _export(client, seeded.bob)) == _comparable(bob_before)
    assert _comparable(await _export(client, seeded.admin)) == _comparable(admin_before)


async def test_import_requires_authentication(anonymous_client: AsyncClient) -> None:
    assert (await anonymous_client.get("/profile/export")).status_code == 401
    assert (await anonymous_client.post("/profile/import", json={})).status_code == 401


def _break(document: dict[str, Any], path: list[Any], value: Any) -> dict[str, Any]:
    target: Any = document
    for step in path[:-1]:
        target = target[step]
    target[path[-1]] = value
    return document


@pytest.mark.parametrize(
    ("path", "value", "fragment"),
    [
        (["format"], "dinatos-backup", "format"),
        (["format_version"], 2, "format_version"),
        (["routines", 0, "name"], "", "name"),
        (["routines", 0, "name"], "x" * 201, "name"),
        (["routines", 1, "exercises", 0, "sets", 0, "set_type"], "bogus", "set_type"),
        (["activities", 0, "started_at"], "yesterday", "started_at"),
        (["profile", "unit_system"], "cubits", "unit_system"),
        (["exercises", 0, "primary_muscles"], ["pinky"], "primary_muscles"),
        (["routines"], "nope", "routines"),
    ],
)
async def test_malformed_files_are_rejected_with_422_and_change_nothing(
    client: AsyncClient, seeded: Seeded, path: list[Any], value: Any, fragment: str
) -> None:
    document = _break(await _export(client, seeded.alice), path, value)
    before = await _export(client, seeded.bob)

    for mode in ("merge", "replace"):
        response = await _import(client, seeded.bob, document, mode)
        assert response.status_code == 422, response.text
        assert fragment in json.dumps(response.json()["detail"])
    assert _comparable(await _export(client, seeded.bob)) == _comparable(before)


async def test_unknown_mode_is_rejected(client: AsyncClient, seeded: Seeded) -> None:
    document = await _export(client, seeded.alice)
    assert (await _import(client, seeded.alice, document, "obliterate")).status_code == 422


def _unknown_exercise(document: dict[str, Any]) -> None:
    document["exercises"] = [e for e in document["exercises"] if e["name"] != "Hill Sprint"]


def _duplicate_exercise(document: dict[str, Any]) -> None:
    document["exercises"].append(dict(document["exercises"][0]))


def _duplicate_ref(document: dict[str, Any]) -> None:
    document["routines"][0]["ref"] = document["routines"][1]["ref"]


def _unknown_ref(document: dict[str, Any]) -> None:
    document["activities"][0]["routine_ref"] = 99


@pytest.mark.parametrize(
    ("mutate", "fragment"),
    [
        (_unknown_exercise, "neither defined"),
        (_duplicate_exercise, "same name more than once"),
        (_duplicate_ref, "reuses a ref"),
        (_unknown_ref, "unknown routine_ref"),
    ],
)
async def test_dangling_references_are_rejected_before_anything_is_written(
    client: AsyncClient, seeded: Seeded, mutate: Any, fragment: str
) -> None:
    document = await _export(client, seeded.alice)
    if mutate is _unknown_exercise:
        # Make "Hill Sprint" unknown to the server too, so only the file could define it.
        sprint = (await client.get("/exercises", params={"search": "Hill Sprint"})).json()[0]
        for kind in ("routines", "activities"):
            for item in (await client.get(f"/{kind}", headers=seeded.alice.headers)).json():
                await client.delete(f"/{kind}/{item['id']}", headers=seeded.alice.headers)
        await client.delete(f"/exercises/{sprint['id']}")
    mutate(document)
    before = await _export(client, seeded.alice)

    response = await _import(client, seeded.alice, document, "replace")

    assert response.status_code == 422, response.text
    assert fragment in json.dumps(response.json()["detail"])
    assert _comparable(await _export(client, seeded.alice)) == _comparable(before)


async def test_clear_data_wipes_the_callers_data_and_unused_custom_exercises(
    client: AsyncClient, seeded: Seeded
) -> None:
    response = await client.delete("/profile/data", headers=seeded.alice.headers)
    assert response.status_code == 200, response.text
    assert response.json()["deleted"]["routines"] == 2
    assert response.json()["deleted"]["activities"] == 2
    assert response.json()["deleted"]["planned_workouts"] == 1

    document = await _export(client, seeded.alice)
    assert document["routines"] == []
    assert document["activities"] == []
    assert document["measurements"] == []
    assert document["profile"] == {"height_cm": 171.5, "unit_system": "imperial"}
    # Bob's data is untouched.
    bob = await _export(client, seeded.bob)
    assert bob["routines"] or bob["activities"] or bob["measurements"]

    # Clearing an already-clean account is a harmless no-op.
    again = await client.delete("/profile/data", headers=seeded.alice.headers)
    assert again.json()["deleted"] == {
        "exercises": 0,
        "routines": 0,
        "activities": 0,
        "measurements": 0,
        "planned_workouts": 0,
    }


async def test_planned_workouts_keep_their_routine_through_an_import(
    client: AsyncClient, seeded: Seeded
) -> None:
    document = await _export(client, seeded.alice)
    assert document["planned_workouts"] == [
        {
            "title": "Push",
            "notes": "heavy",
            "scheduled_at": "2030-06-01T07:30:00Z",
            "duration_minutes": 75,
            "reminder_minutes": 15,
            "routine_ref": 2,
        }
    ]
    carol = await register(client, "carol@example.com")
    await _import(client, carol, document)
    plans = (await client.get("/planned-workouts", headers=carol.headers)).json()
    routines = (await client.get("/routines", headers=carol.headers)).json()
    assert [p["routine_id"] for p in plans] == [
        next(r["id"] for r in routines if r["name"] == "Push")
    ]


async def test_a_planned_workout_with_an_unknown_routine_ref_is_rejected(
    client: AsyncClient, seeded: Seeded
) -> None:
    document = await _export(client, seeded.alice)
    document["planned_workouts"][0]["routine_ref"] = 99
    response = await _import(client, seeded.alice, document)
    assert response.status_code == 422
    assert "unknown routine_ref" in response.text


async def test_clear_data_requires_authentication(anonymous_client: AsyncClient) -> None:
    assert (await anonymous_client.delete("/profile/data")).status_code == 401


async def test_an_export_from_before_rpe_was_dropped_still_imports(client: AsyncClient) -> None:
    document = {
        "format": "dinatos-user-export",
        "format_version": 1,
        "exported_at": "2026-01-01T00:00:00Z",
        "app_version": "0.0.1",
        "profile": {},
        "exercises": [{"name": "Old Lift"}],
        "activities": [
            {
                "title": "Old",
                "started_at": "2026-01-01T10:00:00Z",
                "exercises": [
                    {"exercise": "Old Lift", "sets": [{"weight_kg": 50, "reps": 5, "rpe": 8}]}
                ],
            }
        ],
    }
    response = await client.post("/profile/import", json=document)
    assert response.status_code == 200, response.text
    assert response.json()["created"]["activities"] == 1


async def test_the_completed_flag_survives_an_export_and_import(client: AsyncClient) -> None:
    document = {
        "format": "dinatos-user-export",
        "format_version": 1,
        "exported_at": "2026-01-01T00:00:00Z",
        "app_version": "0.0.1",
        "profile": {},
        "exercises": [{"name": "Ticked Lift"}],
        "activities": [
            {
                "title": "Mixed",
                "started_at": "2026-01-01T10:00:00Z",
                "exercises": [
                    {
                        "exercise": "Ticked Lift",
                        "sets": [{"reps": 5}, {"reps": 5, "completed": False}],
                    }
                ],
            }
        ],
    }
    assert (await client.post("/profile/import", json=document)).status_code == 200
    exported = (await client.get("/profile/export")).json()
    sets = exported["activities"][0]["exercises"][0]["sets"]
    assert [s["completed"] for s in sets] == [True, False]
