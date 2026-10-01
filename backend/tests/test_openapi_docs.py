"""Guards on the API documentation FastAPI serves at `/docs`, `/redoc` and
`/openapi.json`.

These aren't tests of any behaviour so much as a canary: the Flutter app links
straight at the backend's `/docs` to show the Swagger UI in place (see
`frontend/lib/features/docs/`), so the moment any of these stop being served,
or the schema stops describing the routes, the app's API documentation page
turns into a blank frame or a 404 for every user of the web build -- and
nothing else in the suite would notice. The OpenAPI assertions double as a
cheap guard that a new router was actually wired into `main.py`, which is
otherwise only observable by hand.
"""

from typing import Any

from httpx2 import AsyncClient

from dinatos_backend.main import app


async def test_swagger_ui_is_served(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.get("/docs")

    assert response.status_code == 200
    # Swagger UI is a self-contained HTML page: the mount point and the URL it
    # fetches the schema from are what make it functional, so both are asserted
    # rather than just the status code.
    assert "text/html" in response.headers["content-type"]
    schema_url = app.openapi_url
    assert schema_url is not None
    body = response.text
    assert "swagger-ui" in body
    assert schema_url in body


async def test_redoc_is_served(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.get("/redoc")

    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    schema_url = app.openapi_url
    assert schema_url is not None
    assert schema_url in response.text


async def test_openapi_schema_is_served_without_authentication(
    anonymous_client: AsyncClient,
) -> None:
    # Deliberately the `anonymous_client`: the docs have to be readable to get
    # a *token* in the first place, so gating them behind one would be circular.
    response = await anonymous_client.get("/openapi.json")

    assert response.status_code == 200
    assert response.json()["openapi"].startswith("3.")


def test_openapi_schema_documents_every_router() -> None:
    schema: dict[str, Any] = app.openapi()

    assert schema["info"]["title"] == "Dinatos"
    # A non-empty description is what Swagger UI renders above the endpoint
    # list; losing it is silent, so pin it.
    assert schema["info"]["description"]
    # Every router in main.py, so a new one that's included but has no routes
    # (or was never included at all) fails here instead of just being absent.
    # `openapi_tags=` lands in the schema as the top-level `tags` list, which
    # is what Swagger UI groups by and renders each group's blurb from.
    assert {tag["name"] for tag in schema["tags"]} >= {
        "auth",
        "exercises",
        "routines",
        "activities",
        "measurements",
        "profile",
        "imports",
    }
    assert {"/health", "/auth/login", "/exercises", "/routines", "/activities"} <= set(
        schema["paths"]
    )


def test_every_operation_is_summarized_for_the_docs() -> None:
    """Swagger UI's endpoint list is built from each operation's ``summary``.

    A route declared without one still works, still tests green, and shows up
    in the docs as a bare method-and-path with nothing to click on, so this
    asserts every operation carries a non-empty summary.
    """
    schema: dict[str, Any] = app.openapi()

    unsummarized = [
        f"{method.upper()} {path}"
        for path, operations in schema["paths"].items()
        for method, operation in operations.items()
        if isinstance(operation, dict) and not operation.get("summary")
    ]

    assert unsummarized == []
