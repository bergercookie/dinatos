"""The calendar feed: planned workouts as an iCalendar (RFC 5545) document
that Google/Apple/Outlook calendars subscribe to by URL.

The feed is generated on every request from the database, so it is never
stale; what "updating periodically" means is the subscribing app re-fetching
it, which `REFRESH-INTERVAL` / `X-PUBLISHED-TTL` ask for hourly (apps are
free to poll less often, Google notably only every few hours).
"""

import secrets
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from dinatos_backend.models.planned_workout import PlannedWorkout
from dinatos_backend.models.profile import UserProfile
from dinatos_backend.services.backup import normalize_utc

# How far back the feed reaches: enough to see recent history in a calendar
# without shipping every plan the person ever made on each poll.
FEED_LOOKBACK = timedelta(days=90)
REFRESH_INTERVAL = "PT1H"


def new_calendar_token() -> str:
    return secrets.token_urlsafe(32)


async def get_profile_by_calendar_token(db: AsyncSession, token: str) -> UserProfile | None:
    return await db.scalar(select(UserProfile).where(UserProfile.calendar_token == token))


async def feed_planned_workouts(
    db: AsyncSession, owner_id: int, now: datetime | None = None
) -> list[PlannedWorkout]:
    since = (now or datetime.now(UTC)) - FEED_LOOKBACK
    result = await db.scalars(
        select(PlannedWorkout)
        .where(PlannedWorkout.owner_id == owner_id, PlannedWorkout.scheduled_at >= since)
        .order_by(PlannedWorkout.scheduled_at, PlannedWorkout.id)
    )
    return list(result)


def _escape(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")
        .replace("\r", "\\n")
    )


def _fold(line: str) -> str:
    """Folds a content line at 75 octets, never inside a UTF-8 sequence."""
    encoded = line.encode()
    if len(encoded) <= 75:
        return line
    parts: list[str] = []
    current = b""
    limit = 75
    for char in line:
        piece = char.encode()
        if len(current) + len(piece) > limit:
            parts.append(current.decode())
            current = b""
            limit = 74  # continuation lines start with a space
        current += piece
    parts.append(current.decode())
    return "\r\n ".join(parts)


def _stamp(value: datetime) -> str:
    return normalize_utc(value).strftime("%Y%m%dT%H%M%SZ")


def build_ics(workouts: list[PlannedWorkout], *, calendar_name: str = "Dinatos workouts") -> str:
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Dinatos//Planned workouts//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        f"X-WR-CALNAME:{_escape(calendar_name)}",
        f"REFRESH-INTERVAL;VALUE=DURATION:{REFRESH_INTERVAL}",
        f"X-PUBLISHED-TTL:{REFRESH_INTERVAL}",
    ]
    for workout in workouts:
        start = normalize_utc(workout.scheduled_at)
        end = start + timedelta(minutes=workout.duration_minutes)
        updated = normalize_utc(workout.updated_at) if workout.updated_at else start
        description = workout.notes or ""
        if workout.completed_activity_id is not None:
            description = (description + "\n" if description else "") + "Done."
        lines += [
            "BEGIN:VEVENT",
            f"UID:planned-{workout.id}@dinatos",
            f"DTSTAMP:{_stamp(updated)}",
            # Lets a subscribing app tell that an event it already has changed.
            f"SEQUENCE:{int(updated.timestamp())}",
            f"DTSTART:{_stamp(start)}",
            f"DTEND:{_stamp(end)}",
            f"SUMMARY:{_escape(workout.title)}",
        ]
        if description:
            lines.append(f"DESCRIPTION:{_escape(description)}")
        lines.append("STATUS:CONFIRMED")
        lines.append("TRANSP:OPAQUE")
        if workout.reminder_minutes is not None:
            lines += [
                "BEGIN:VALARM",
                "ACTION:DISPLAY",
                f"DESCRIPTION:{_escape(workout.title)}",
                f"TRIGGER:-PT{workout.reminder_minutes}M",
                "END:VALARM",
            ]
        lines.append("END:VEVENT")
    lines.append("END:VCALENDAR")
    return "\r\n".join(_fold(line) for line in lines) + "\r\n"
