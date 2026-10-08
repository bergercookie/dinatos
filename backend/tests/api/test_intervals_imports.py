from collections.abc import Callable, Iterator
from typing import Any

import httpx2 as httpx
import pytest
from httpx2 import AsyncClient

from dinatos_backend.api.routers.intervals_imports import get_intervals_client
from dinatos_backend.main import app
from dinatos_backend.services.intervals_client import IntervalsClient
from dinatos_backend.services.personas import analyse_personas

ACTIVITIES: list[dict[str, Any]] = [
    {
        "id": "i100",
        "name": "Morning run",
        "type": "Run",
        "start_date_local": "2026-03-01T07:30:00",
        "moving_time": 1800,
        "distance": 5000,
    },
    {
        "id": "i101",
        "name": "Leg day (from Hevy)",
        "type": "WeightTraining",
        "start_date_local": "2026-03-02T18:00:00",
        "moving_time": 3600,
    },
    {"id": "i102", "_note": "STRAVA activities are not available"},
]
SOURCE = {"athlete_id": "0", "api_key": "secret", "oldest": "2026-03-01", "newest": "2026-03-31"}


Answer = httpx.Response | Callable[[httpx.Request], httpx.Response]
SetAnswer = Callable[[Answer], None]


@pytest.fixture
def intervals() -> Iterator[SetAnswer]:
    """Point the app at a fake Intervals.icu; call the result to set its answer."""
    answer: list[Answer] = [httpx.Response(200, json=ACTIVITIES)]

    def handler(request: httpx.Request) -> httpx.Response:
        current = answer[0]
        return current if isinstance(current, httpx.Response) else current(request)

    app.dependency_overrides[get_intervals_client] = lambda: IntervalsClient(
        transport=httpx.MockTransport(handler)
    )
    yield lambda response: answer.__setitem__(0, response)
    app.dependency_overrides.pop(get_intervals_client, None)


async def _preview(client: AsyncClient, **overrides: str) -> httpx.Response:
    return await client.post("/imports/intervals/preview", json={**SOURCE, **overrides})


async def _import(
    client: AsyncClient, ids: list[str], *, force: bool = False, **overrides: Any
) -> httpx.Response:
    return await client.post(
        "/imports/intervals/activities",
        params={"force": "true"} if force else {},
        json={**SOURCE, "activity_ids": ids, **overrides},
    )


@pytest.mark.usefixtures("intervals")
async def test_preview_lists_activities_without_writing_anything(client: AsyncClient) -> None:
    response = await _preview(client)

    assert response.status_code == 200
    activities = response.json()["activities"]
    assert [a["id"] for a in activities] == ["i101", "i100", "i102"]
    assert activities[1] == {
        "id": "i100",
        "name": "Morning run",
        "type": "Run",
        "started_at": "2026-03-01T07:30:00",
        "duration_seconds": 1800,
        "distance_km": 5.0,
        "importable": True,
        "unimportable_reason": None,
        "already_imported": False,
        "imported_at": None,
        "possible_duplicate_of": None,
    }
    assert activities[2]["importable"] is False
    assert (await client.get("/activities")).json() == []


@pytest.mark.usefixtures("intervals")
async def test_preview_flags_a_workout_hevy_already_synced(client: AsyncClient) -> None:
    await client.post(
        "/activities",
        json={"title": "Leg Day", "started_at": "2026-03-02T18:05:00", "exercises": []},
    )

    by_id = {a["id"]: a for a in (await _preview(client)).json()["activities"]}

    assert by_id["i101"]["possible_duplicate_of"] == "Leg Day"
    assert by_id["i100"]["possible_duplicate_of"] is None


@pytest.mark.usefixtures("intervals")
async def test_import_only_creates_the_chosen_activities(client: AsyncClient) -> None:
    response = await _import(client, ["i100"])

    assert response.status_code == 200
    body = response.json()
    assert (body["activities_created"], body["exercises_created"]) == (1, 1)
    assert [e["name"] for e in body["created_exercises"]] == ["Running"]
    activities = (await client.get("/activities")).json()
    assert [a["title"] for a in activities] == ["Morning run"]
    exercise = activities[0]["exercises"][0]
    running = (await client.get(f"/exercises/{exercise['exercise_id']}")).json()
    assert running["name"] == "Running"
    assert exercise["sets"][0]["distance_km"] == 5.0
    assert exercise["sets"][0]["duration_seconds"] == 1800


@pytest.mark.usefixtures("intervals")
async def test_importing_again_is_a_409_and_the_preview_says_why(client: AsyncClient) -> None:
    assert (await _import(client, ["i100"])).status_code == 200

    second = await _import(client, ["i100", "i101"])

    assert second.status_code == 409
    detail = second.json()["detail"]
    assert "already imported" in detail["message"]
    assert list(detail["already_imported"]) == ["i100"]
    # All or nothing: i101 was not imported alongside it.
    assert len((await client.get("/activities")).json()) == 1
    by_id = {a["id"]: a for a in (await _preview(client)).json()["activities"]}
    assert by_id["i100"]["already_imported"] is True
    assert by_id["i100"]["imported_at"] is not None
    assert by_id["i101"]["already_imported"] is False


@pytest.mark.usefixtures("intervals")
async def test_force_imports_an_already_imported_activity_again(client: AsyncClient) -> None:
    await _import(client, ["i100"])

    response = await _import(client, ["i100"], force=True)

    assert response.status_code == 200
    assert response.json()["activities_created"] == 1
    assert response.json()["exercises_created"] == 0
    assert len((await client.get("/activities")).json()) == 2


@pytest.mark.usefixtures("intervals")
async def test_deleting_an_imported_activity_lets_it_be_imported_again(client: AsyncClient) -> None:
    await _import(client, ["i100"])
    (activity,) = (await client.get("/activities")).json()
    await client.delete(f"/activities/{activity['id']}")

    response = await _import(client, ["i100"])

    assert response.status_code == 200
    assert len((await client.get("/activities")).json()) == 1


@pytest.mark.usefixtures("intervals")
async def test_clearing_the_account_forgets_what_was_imported(client: AsyncClient) -> None:
    await _import(client, ["i100"])
    await client.delete("/profile/data")

    assert (await _import(client, ["i100"])).status_code == 200


@pytest.mark.usefixtures("intervals")
async def test_unknown_and_unimportable_ids_are_422(client: AsyncClient) -> None:
    response = await _import(client, ["i100", "i102", "ghost"])

    assert response.status_code == 422
    detail = response.json()["detail"]
    assert (detail["not_found"], detail["unimportable"]) == (["ghost"], ["i102"])
    assert (await client.get("/activities")).json() == []


@pytest.mark.usefixtures("intervals")
@pytest.mark.parametrize(
    "overrides",
    [
        {"athlete_id": "../../etc"},
        {"athlete_id": "i12/activities"},
        {"api_key": ""},
        {"newest": "2026-02-01"},
        {"oldest": "not-a-date"},
    ],
)
async def test_a_bad_source_is_rejected_before_calling_intervals(
    client: AsyncClient, overrides: dict[str, str]
) -> None:
    assert (await _preview(client, **overrides)).status_code == 422
    body = {**SOURCE, "activity_ids": ["i100"], **overrides}
    assert (await client.post("/imports/intervals/activities", json=body)).status_code == 422


@pytest.mark.usefixtures("intervals")
async def test_an_import_needs_at_least_one_id(client: AsyncClient) -> None:
    assert (await _import(client, [])).status_code == 422


@pytest.mark.usefixtures("intervals")
@pytest.mark.parametrize("athlete_id", ["0", "i12345", "12345"])
async def test_valid_athlete_ids_are_accepted(client: AsyncClient, athlete_id: str) -> None:
    assert (await _preview(client, athlete_id=athlete_id)).status_code == 200


async def test_newest_defaults_to_today(
    client: AsyncClient,
    intervals: SetAnswer,
) -> None:
    seen: list[dict[str, str]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(dict(request.url.params))
        return httpx.Response(200, json=[])

    intervals(handler)
    source = {k: v for k, v in SOURCE.items() if k != "newest"}

    assert (await client.post("/imports/intervals/preview", json=source)).status_code == 200
    assert seen[0]["oldest"] == "2026-03-01"
    assert seen[0]["newest"] >= "2026-10-07"  # today, whichever day the suite runs


async def test_a_rejected_key_is_400_not_401(
    client: AsyncClient,
    intervals: SetAnswer,
) -> None:
    # A 401 from Dinatos would make the app log the person out.
    intervals(httpx.Response(401))

    for response in (await _preview(client), await _import(client, ["i100"])):
        assert response.status_code == 400
        assert "API key" in response.json()["detail"]


async def test_intervals_being_down_is_502(
    client: AsyncClient,
    intervals: SetAnswer,
) -> None:
    intervals(httpx.Response(503))

    assert (await _preview(client)).status_code == 502
    assert (await _import(client, ["i100"])).status_code == 502


async def test_the_api_key_is_never_echoed_back(
    client: AsyncClient,
    intervals: SetAnswer,
) -> None:
    intervals(httpx.Response(401))
    responses = [await _preview(client), await _import(client, ["i100"])]
    intervals(httpx.Response(200, json=ACTIVITIES))
    responses += [await _preview(client), await _import(client, ["i100"])]

    assert all("secret" not in response.text for response in responses)


async def test_endpoints_require_authentication(anonymous_client: AsyncClient) -> None:
    assert (await _preview(anonymous_client)).status_code == 401
    assert (await _import(anonymous_client, ["i100"])).status_code == 401


async def test_the_default_client_talks_to_the_real_intervals_host(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    # No override: the dependency builds the real client. Stop it at the
    # transport so no network is touched, and check where it was headed.
    hosts: list[str] = []
    real = httpx.AsyncClient

    def fake_client(**kwargs: Any) -> httpx.AsyncClient:
        def handler(request: httpx.Request) -> httpx.Response:
            hosts.append(str(request.url))
            return httpx.Response(200, json=[])

        return real(**{**kwargs, "transport": httpx.MockTransport(handler)})

    monkeypatch.setattr(httpx, "AsyncClient", fake_client)

    assert (await _preview(client)).status_code == 200
    assert hosts[0].startswith("https://intervals.icu/api/v1/athlete/0/activities?")


@pytest.mark.usefixtures("intervals")
async def test_imported_runs_count_towards_the_persona_endurance_mix(client: AsyncClient) -> None:
    """The persona analysis (Personas page, MCP `get_persona_stats`) works on
    what the REST API returns, so an imported run must come out as endurance
    training there: 30 minutes of running is 10 set-equivalents -- exactly
    enough for a training match -- and the distance-runner persona wins it.
    """
    await _import(client, ["i100"])

    analysis = analyse_personas(
        activities=(await client.get("/activities")).json(),
        measurements=[],
        catalog={e["id"]: e for e in (await client.get("/exercises")).json()},
        range_="all",
    )

    assert analysis["training_units"] == 10.0
    assert analysis["training_share"]["endurance"] == 1.0
    assert analysis["training_enough"] is True
    assert analysis["best_training_match"] == "distance_runner"
