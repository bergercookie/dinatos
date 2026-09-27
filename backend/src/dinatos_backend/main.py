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

app = FastAPI(title="Dinatos", version=__version__, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_allowed_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
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
