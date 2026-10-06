"""Startup/shutdown hooks for the FastAPI app.

Lives in `api/`, not directly in `main.py`, so it can depend on `db` and
`services` -- `tach.toml`'s module graph keeps the top-level app module
itself limited to `config` and `api`, routing everything else through this
layer instead.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from dinatos_backend.api.mcp import mcp_gateway
from dinatos_backend.db import async_session_factory
from dinatos_backend.services.auth import bootstrap_admin_user
from dinatos_backend.services.exercise import bootstrap_default_exercises


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    # Migrations are expected to have already run by this point (the
    # Docker image's entrypoint does this; `just dev` does too) -- this
    # only creates rows, never touches schema.
    async with async_session_factory() as db:
        # Exercises first: a new account's starter routines are built from them.
        await bootstrap_default_exercises(db)
        await bootstrap_admin_user(db)
    async with mcp_gateway.running():
        yield
