from httpx2 import AsyncClient

from dinatos_backend.config import get_settings


async def test_preflight_from_an_allowed_origin_gets_cors_headers(
    anonymous_client: AsyncClient,
) -> None:
    """The Flutter web frontend is served from a different origin than the
    backend -- without CORS headers on the response, the browser itself
    (not the server) blocks the request before it ever reaches a route.
    See docs/architecture/frontend.md's "CORS" section for how this was found.
    """
    response = await anonymous_client.options(
        "/auth/register",
        headers={
            "Origin": "http://example.com",
            "Access-Control-Request-Method": "POST",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "*"


async def test_cors_allowed_origins_defaults_to_wildcard() -> None:
    assert get_settings().cors_allowed_origins == ["*"]
