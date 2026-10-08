"""Read-only client for the Intervals.icu API (https://intervals.icu), used
by the one-time activity import (`services.intervals_import`).

Auth is HTTP Basic with the literal username `API_KEY` and the person's own
key as the password. The key is sent per request and never stored or logged.
The base URL is fixed, so no request can be steered at another host.
"""

from datetime import date
from typing import Any

import httpx2 as httpx

_BASE_URL = "https://intervals.icu/api/v1"


class IntervalsAuthError(Exception):
    """Intervals.icu rejected the API key, or the athlete id isn't reachable
    with it.
    """


class IntervalsUnavailableError(Exception):
    """Intervals.icu couldn't be reached, or answered with something unusable."""


class IntervalsClient:
    def __init__(self, *, transport: httpx.AsyncBaseTransport | None = None) -> None:
        # Injectable for tests only (a fake transport, no real network).
        self._transport = transport

    async def list_activities(
        self, athlete_id: str, api_key: str, oldest: date, newest: date
    ) -> list[dict[str, Any]]:
        try:
            async with httpx.AsyncClient(
                base_url=_BASE_URL, timeout=30.0, transport=self._transport
            ) as client:
                response = await client.get(
                    f"/athlete/{athlete_id}/activities",
                    params={"oldest": oldest.isoformat(), "newest": newest.isoformat()},
                    auth=("API_KEY", api_key),
                )
        except httpx.HTTPError as error:
            raise IntervalsUnavailableError("could not reach Intervals.icu") from error

        if response.status_code in (
            httpx.codes.UNAUTHORIZED,
            httpx.codes.FORBIDDEN,
            httpx.codes.NOT_FOUND,
        ):
            raise IntervalsAuthError("Intervals.icu rejected the API key or athlete id")
        if response.status_code >= httpx.codes.BAD_REQUEST:
            raise IntervalsUnavailableError(f"Intervals.icu answered {response.status_code}")
        try:
            payload = response.json()
        except ValueError as error:
            raise IntervalsUnavailableError("Intervals.icu sent an unreadable response") from error
        if not isinstance(payload, list):
            raise IntervalsUnavailableError("Intervals.icu sent an unexpected response")
        return [item for item in payload if isinstance(item, dict)]
