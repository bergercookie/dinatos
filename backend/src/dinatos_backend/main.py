"""The FastAPI application."""

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import Response
from starlette.types import Scope

from dinatos_backend import __version__
from dinatos_backend.api.lifespan import lifespan
from dinatos_backend.api.routers import (
    activities,
    auth,
    exercises,
    imports,
    measurements,
    profile,
    workouts,
)
from dinatos_backend.config import get_settings

app = FastAPI(
    title="Dinatos",
    version=__version__,
    lifespan=lifespan,
    description=(
        "The Dinatos REST API.\n\n"
        "Everything except `GET /health` needs an "
        "`Authorization: Bearer <token>` header. Call `POST /auth/register` or "
        "`POST /auth/login` to get one -- those two, and only those two, work "
        "without it (`/auth/me` and `/auth/logout` are themselves "
        "authenticated).\n\n"
        "This is a self-hosted service: `/docs` (this page), `/redoc` and the "
        "raw `/openapi.json` are served by the same app, so they are only "
        "reachable to whoever can already reach the API itself."
    ),
    openapi_tags=[
        {"name": "auth", "description": "Registration, login and session revocation."},
        {"name": "exercises", "description": "The exercise catalog, shared by every user."},
        {"name": "workouts", "description": "Workout templates: exercises and sets, no dates."},
        {"name": "activities", "description": "Logged instances of a workout, actually performed."},
        {"name": "measurements", "description": "Body weight, fat percentage and circumferences."},
        {"name": "profile", "description": "Per-user display settings."},
        {"name": "imports", "description": "One-shot migration of a Hevy CSV export."},
    ],
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_allowed_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    # `X-Total-Count` (GET /exercises' pagination total) is otherwise
    # invisible to browser JS on a cross-origin response -- only headers
    # named here are exposed, regardless of allow_headers above.
    expose_headers=["X-Total-Count"],
)
app.include_router(auth.router)
app.include_router(exercises.router)
app.include_router(workouts.router)
app.include_router(activities.router)
app.include_router(profile.router)
app.include_router(measurements.router)
app.include_router(imports.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


class _WebApp(StaticFiles):
    """Serves a built Flutter web app, falling back to `index.html` for any
    path that doesn't resolve to an actual file.

    Flutter web's default (hash-based) routing never sends its client-side
    routes to the server at all -- a browser on `/#/workouts/1` only ever
    requests `/` -- so in practice this fallback is a safety net for the odd
    direct request to a path that isn't a real asset, not something the app
    relies on to navigate.
    """

    async def get_response(self, path: str, scope: Scope) -> Response:
        try:
            return await super().get_response(path, scope)
        except StarletteHTTPException as exc:
            if exc.status_code == 404:
                return await super().get_response("index.html", scope)
            raise


def _mount_web_ui(app: FastAPI, web_dir: Path) -> None:
    """Serves a built Flutter web app under `/`, mounted last and
    deliberately not itself an included router -- every path above
    (including `/health`) is matched first, so this only ever serves what
    nothing else claimed. A no-op when `web_dir` doesn't exist, which is the
    common case outside the Docker image (`just backend run`, these tests)
    -- see `Settings.web_dir`.
    """
    if web_dir.is_dir():
        app.mount("/", _WebApp(directory=web_dir, html=True), name="web-ui")


_mount_web_ui(app, Path(get_settings().web_dir))
