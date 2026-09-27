from collections.abc import Callable
from typing import Any

import httpx
import pytest

from dinatos_backend.services.tutorials.workoutx import WorkoutXProvider

_MATCH = {
    "id": "0001",
    "name": "3/4 Sit-up",
    "gifUrl": "https://api.workoutxapp.com/v1/gifs/0001.gif",
    "instructions": ["Lie down.", "Sit up ¾ of the way."],
    "equipment": "Body Weight",
    "target": "Abs",
    "secondaryMuscles": ["Hip Flexors"],
}


def _provider(
    handler: Callable[[httpx.Request], httpx.Response], api_key: str = "wx_test"
) -> WorkoutXProvider:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(handler), base_url="https://api.workoutxapp.com/v1"
    )
    return WorkoutXProvider(api_key, client=client)


def _wrapped(matches: list[dict[str, Any]]) -> dict[str, Any]:
    """The real response shape: {"total", "count", "data": [...]}, not the
    bare array this endpoint's own docs example showed -- confirmed by a
    real `KeyError: 0` in production from treating `data` as if it were
    the top-level list itself.
    """
    return {"total": len(matches), "count": len(matches), "data": matches}


async def test_get_tutorial_sends_the_api_key_header_and_parses_a_match() -> None:
    seen_headers: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen_headers.update(request.headers)
        return httpx.Response(200, json=_wrapped([_MATCH]))

    provider = _provider(handler, api_key="wx_secret")
    tutorial = await provider.get_tutorial("3/4 Sit-up")

    assert seen_headers["x-workoutx-key"] == "wx_secret"
    assert tutorial is not None
    assert tutorial.source == "workoutx"
    assert tutorial.gif_urls == ["https://api.workoutxapp.com/v1/gifs/0001.gif"]
    assert tutorial.instructions == _MATCH["instructions"]
    assert tutorial.primary_muscles == ["Abs"]
    assert tutorial.secondary_muscles == ["Hip Flexors"]


async def test_get_tutorial_prefers_an_exact_name_match_among_results() -> None:
    partial_match = {**_MATCH, "id": "9999", "name": "3/4 Sit-up Variation"}

    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_wrapped([partial_match, _MATCH]))

    provider = _provider(handler)
    tutorial = await provider.get_tutorial("3/4 Sit-up")

    assert tutorial is not None
    assert tutorial.gif_urls == [_MATCH["gifUrl"]]


async def test_get_tutorial_returns_none_on_a_404() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            404, json={"error": "Not Found", "message": "no match", "status": 404}
        )

    provider = _provider(handler)

    assert await provider.get_tutorial("Not A Real Exercise") is None


async def test_get_tutorial_returns_none_on_an_empty_result_list() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_wrapped([]))

    provider = _provider(handler)

    assert await provider.get_tutorial("Not A Real Exercise") is None


async def test_get_tutorial_still_accepts_a_bare_array_response() -> None:
    """Defensive, not the confirmed real shape (see `_wrapped`'s doc) --
    this endpoint's own docs example showed one, so a bare array is
    accepted too rather than assuming the dict envelope unconditionally.
    """

    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=[_MATCH])

    provider = _provider(handler)
    tutorial = await provider.get_tutorial("3/4 Sit-up")

    assert tutorial is not None
    assert tutorial.gif_urls == [_MATCH["gifUrl"]]


async def test_get_tutorial_raises_on_an_unauthorized_response() -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            401, json={"error": "Unauthorized", "message": "bad key", "status": 401}
        )

    provider = _provider(handler, api_key="wx_bad")

    with pytest.raises(httpx.HTTPStatusError):
        await provider.get_tutorial("3/4 Sit-up")
