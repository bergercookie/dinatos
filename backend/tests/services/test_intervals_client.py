from collections.abc import Callable
from datetime import date

import httpx2 as httpx
import pytest

from dinatos_backend.services.intervals_client import (
    IntervalsAuthError,
    IntervalsClient,
    IntervalsUnavailableError,
)


def _client(handler: Callable[[httpx.Request], httpx.Response]) -> IntervalsClient:
    return IntervalsClient(transport=httpx.MockTransport(handler))


def _always(response: httpx.Response) -> Callable[[httpx.Request], httpx.Response]:
    return lambda _request: response


async def _list(client: IntervalsClient) -> list[dict[str, object]]:
    return await client.list_activities("i42", "secret", date(2026, 1, 1), date(2026, 1, 31))


async def test_list_activities_sends_basic_auth_and_the_date_window() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=[{"id": "i1"}, "junk", {"id": "i2"}])

    activities = await _list(_client(handler))

    assert activities == [{"id": "i1"}, {"id": "i2"}]  # non-objects are dropped
    request = seen[0]
    assert request.url.host == "intervals.icu"
    assert request.url.path == "/api/v1/athlete/i42/activities"
    assert dict(request.url.params) == {"oldest": "2026-01-01", "newest": "2026-01-31"}
    # Basic auth with the literal username API_KEY and the key as password.
    assert request.headers["authorization"] == "Basic QVBJX0tFWTpzZWNyZXQ="


@pytest.mark.parametrize("status", [401, 403, 404])
async def test_a_rejected_key_or_unknown_athlete_is_an_auth_error(status: int) -> None:
    with pytest.raises(IntervalsAuthError):
        await _list(_client(_always(httpx.Response(status))))


async def test_a_server_error_is_unavailable() -> None:
    with pytest.raises(IntervalsUnavailableError, match="500"):
        await _list(_client(_always(httpx.Response(500))))


async def test_a_network_failure_is_unavailable() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("boom")

    with pytest.raises(IntervalsUnavailableError, match="could not reach"):
        await _list(_client(handler))


async def test_an_unreadable_body_is_unavailable() -> None:
    with pytest.raises(IntervalsUnavailableError, match="unreadable"):
        await _list(_client(_always(httpx.Response(200, content=b"<html>"))))


async def test_a_non_list_body_is_unavailable() -> None:
    with pytest.raises(IntervalsUnavailableError, match="unexpected"):
        await _list(_client(_always(httpx.Response(200, json={"id": "i1"}))))
