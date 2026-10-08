import re
from datetime import UTC, datetime, timedelta

from httpx2 import AsyncClient

from dinatos_backend.models.planned_workout import PlannedWorkout
from dinatos_backend.services.calendar import build_ics


async def _enable(client: AsyncClient) -> str:
    response = await client.post("/profile/calendar")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["path"] == f"/calendar/{body['token']}.ics"
    return str(body["token"])


async def test_the_feed_is_off_until_enabled(client: AsyncClient) -> None:
    assert (await client.get("/profile/calendar")).json() == {"token": None, "path": None}
    token = await _enable(client)
    assert (await client.get("/profile/calendar")).json()["token"] == token


async def test_the_feed_needs_no_login_and_lists_the_plans(
    client: AsyncClient, anonymous_client: AsyncClient
) -> None:
    soon = datetime.now(UTC) + timedelta(days=2)
    await client.post(
        "/planned-workouts",
        json={
            "scheduled_at": soon.isoformat(),
            "title": "Legs; heavy, really",
            "notes": "Squat\nDeadlift",
            "duration_minutes": 90,
            "reminder_minutes": 45,
        },
    )
    token = await _enable(client)

    anonymous_client.headers.pop("Authorization", None)
    response = await anonymous_client.get(f"/calendar/{token}.ics")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/calendar")
    text = response.text
    assert text.startswith("BEGIN:VCALENDAR\r\n")
    assert text.endswith("END:VCALENDAR\r\n")
    assert "REFRESH-INTERVAL;VALUE=DURATION:PT1H" in text
    assert "SUMMARY:Legs\\; heavy\\, really" in text
    assert "DESCRIPTION:Squat\\nDeadlift" in text
    assert "TRIGGER:-PT45M" in text
    assert f"DTSTART:{soon.strftime('%Y%m%dT%H%M%S')}Z" in text
    end = soon + timedelta(minutes=90)
    assert f"DTEND:{end.strftime('%Y%m%dT%H%M%S')}Z" in text
    assert re.search(r"UID:planned-\d+@dinatos", text)


async def test_an_unknown_or_rotated_or_disabled_token_is_404(
    client: AsyncClient,
) -> None:
    assert (await client.get("/calendar/nope.ics")).status_code == 404
    old = await _enable(client)
    new = await _enable(client)
    assert old != new
    assert (await client.get(f"/calendar/{old}.ics")).status_code == 404
    assert (await client.get(f"/calendar/{new}.ics")).status_code == 200
    assert (await client.delete("/profile/calendar")).status_code == 204
    assert (await client.get(f"/calendar/{new}.ics")).status_code == 404
    assert (await client.get("/profile/calendar")).json()["token"] is None


async def test_the_feed_only_has_the_owners_plans_and_skips_ancient_ones(
    client: AsyncClient,
) -> None:
    await client.post(
        "/planned-workouts",
        json={"scheduled_at": "2001-01-01T00:00:00Z", "title": "Ancient"},
    )
    soon = (datetime.now(UTC) + timedelta(days=1)).isoformat()
    await client.post("/planned-workouts", json={"scheduled_at": soon, "title": "Upcoming"})
    token = await _enable(client)
    text = (await client.get(f"/calendar/{token}.ics")).text
    assert "Upcoming" in text
    assert "Ancient" not in text


def test_long_lines_fold_at_75_octets_without_splitting_characters() -> None:
    workout = PlannedWorkout(
        id=1,
        owner_id=1,
        title="é" * 100,
        scheduled_at=datetime(2030, 1, 1, tzinfo=UTC),
        updated_at=datetime(2030, 1, 1, tzinfo=UTC),
        duration_minutes=60,
        reminder_minutes=None,
        completed_activity_id=7,
    )
    text = build_ics([workout])
    for physical in text.split("\r\n"):
        assert len(physical.encode()) <= 75
    unfolded = text.replace("\r\n ", "")
    assert "SUMMARY:" + "é" * 100 in unfolded
    assert "DESCRIPTION:Done." in unfolded
    assert "VALARM" not in text
