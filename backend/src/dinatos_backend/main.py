"""The FastAPI application."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

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
