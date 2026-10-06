"""The MCP server, hosted by the API itself at `/mcp` (streamable HTTP).

An LLM client (Claude, ...) is pointed at `https://<your dinatos>/mcp` with an
API key (Settings > API keys) as `Authorization: Bearer dnk_...` -- nothing to
install locally. Each tool acts as the key's owner, by calling the ordinary
REST API in-process with that same key, so the MCP can do exactly what the app
can for that person (same validation, same ownership rules) and nothing else.

Only API keys are accepted here: not a password, and not a login session's
token. Stateless by design: every request is self-contained (the key travels
with it), which is what lets it sit behind any proxy or load balancer.
"""

import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from contextvars import ContextVar
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal

import httpx2
from mcp.server.fastmcp import FastMCP
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from mcp.server.transport_security import TransportSecuritySettings
from starlette.datastructures import Headers
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from dinatos_backend.schemas.activity import ActivityExerciseCreate
from dinatos_backend.schemas.routine import RoutineExerciseCreate
from dinatos_backend.services.api_keys import looks_like_api_key
from dinatos_backend.services.personas import analyse_personas

INSTRUCTIONS = (
    "Manage a Dinatos workout tracker: browse and add exercises, create routine "
    "templates, log activities, and see which athlete personas the person's body and "
    "training resemble. Look up exercise ids with list_exercises before creating a "
    "routine or logging an activity that references one."
)


@dataclass(frozen=True)
class _Caller:
    app: ASGIApp
    authorization: str


_caller: ContextVar[_Caller | None] = ContextVar("dinatos_mcp_caller", default=None)


class McpApiError(RuntimeError):
    """The REST API refused a call a tool made; its `detail` is the message."""


async def _api(
    method: str, path: str, *, params: dict[str, Any] | None = None, body: Any = None
) -> Any:
    caller = _caller.get()
    if caller is None:  # pragma: no cover - the gateway always sets it
        raise McpApiError("not authenticated")
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=caller.app),
        base_url="http://dinatos.internal",
        headers={"Authorization": caller.authorization},
    ) as client:
        response = await client.request(method, path, params=params, json=body)
    if response.status_code >= httpx2.codes.BAD_REQUEST:
        # The app's own errors are always JSON with a `detail`.
        raise McpApiError(f"{response.status_code}: {response.json().get('detail')}")
    return response.json()


def build_mcp_server() -> FastMCP:
    mcp = FastMCP("dinatos", instructions=INSTRUCTIONS)

    @mcp.tool()
    async def list_exercises(search: str | None = None) -> list[dict[str, Any]]:
        """List the exercise catalog, optionally filtered by a case-insensitive
        name search. Use this to find an exercise's id before referencing it
        from create_routine or log_activity.
        """
        result: list[dict[str, Any]] = await _api(
            "GET", "/exercises", params={"search": search} if search else None
        )
        return result

    @mcp.tool()
    async def create_exercise(
        name: str,
        tracks_weight: bool = True,
        tracks_reps: bool = True,
        tracks_distance: bool = False,
        tracks_duration: bool = False,
    ) -> dict[str, Any]:
        """Add a new exercise to the shared catalog. The tracks_* flags say
        which fields are relevant when logging a set of it (e.g. a run tracks
        distance and duration, not weight and reps).
        """
        result: dict[str, Any] = await _api(
            "POST",
            "/exercises",
            body={
                "name": name,
                "tracks_weight": tracks_weight,
                "tracks_reps": tracks_reps,
                "tracks_distance": tracks_distance,
                "tracks_duration": tracks_duration,
            },
        )
        return result

    @mcp.tool()
    async def list_routines() -> list[dict[str, Any]]:
        """List your saved routine templates, with their prescribed exercises and sets."""
        result: list[dict[str, Any]] = await _api("GET", "/routines")
        return result

    @mcp.tool()
    async def create_routine(
        name: str, exercises: list[RoutineExerciseCreate], description: str | None = None
    ) -> dict[str, Any]:
        """Create a saved routine template: a name plus a prescribed list of
        exercises and sets. Sets here are targets (target_weight_kg,
        target_reps, ...), not performed values -- use log_activity for those.
        """
        result: dict[str, Any] = await _api(
            "POST",
            "/routines",
            body={
                "name": name,
                "description": description,
                "exercises": [e.model_dump(mode="json") for e in exercises],
            },
        )
        return result

    @mcp.tool()
    async def list_activities(
        since: datetime | None = None, until: datetime | None = None
    ) -> list[dict[str, Any]]:
        """List logged activities (performed sessions), most recent first,
        optionally bounded by start time.
        """
        params = {
            key: value.isoformat()
            for key, value in {"since": since, "until": until}.items()
            if value is not None
        }
        result: list[dict[str, Any]] = await _api("GET", "/activities", params=params or None)
        return result

    @mcp.tool()
    async def log_activity(
        title: str,
        started_at: datetime,
        exercises: list[ActivityExerciseCreate],
        description: str | None = None,
        ended_at: datetime | None = None,
        routine_id: int | None = None,
    ) -> dict[str, Any]:
        """Log a completed activity: what was actually done, and when. May
        reference one of your own routine templates by id (routine_id) -- not
        someone else's, and not required for an ad-hoc session. Sets count as
        done unless you pass completed=false for one.
        """
        result: dict[str, Any] = await _api(
            "POST",
            "/activities",
            body={
                "title": title,
                "description": description,
                "started_at": started_at.isoformat(),
                "ended_at": ended_at.isoformat() if ended_at is not None else None,
                "routine_id": routine_id,
                "exercises": [e.model_dump(mode="json") for e in exercises],
            },
        )
        return result

    @mcp.tool()
    async def get_persona_stats(
        range: Literal["month", "quarter", "year", "all"] = "quarter",
    ) -> dict[str, Any]:
        """The Personas page as data: how closely the person's body (from their
        measurements and profile height) and their recent training (the sets they
        completed over `range`: month = 30 days, quarter = 90, year = 365) match each
        athlete persona -- sprinter, distance runner, weightlifter, powerlifter,
        bodybuilder, gymnast. Returns 0-100 scores per persona (null when there is too
        little data), the body features and training mix they come from, per-feature
        and per-focus breakdowns, the best matches, and which measurements to log to
        sharpen the result.
        """
        measurements = await _api("GET", "/measurements")
        activities = await _api("GET", "/activities")
        exercises = await _api("GET", "/exercises")
        profile = await _api("GET", "/profile")
        analysis = analyse_personas(
            activities=activities,
            measurements=measurements,
            catalog={e["id"]: e for e in exercises},
            height_cm=profile.get("height_cm"),
            range_=range,
        )
        # Round-trips through JSON so every value is a plain, serialisable one.
        result: dict[str, Any] = json.loads(json.dumps(analysis))
        return result

    return mcp


class McpGateway:
    """The ASGI app mounted at `/mcp`: authenticates the API key, remembers who
    is calling for the tools, and hands the request to the MCP transport.

    `running()` must be active (the app's lifespan does this) for requests to be
    served; a fresh transport is built each time it starts, so tests and
    restarts never reuse a spent one.
    """

    def __init__(self) -> None:
        self._server = build_mcp_server()
        self._manager: StreamableHTTPSessionManager | None = None

    @asynccontextmanager
    async def running(self) -> AsyncIterator[None]:
        manager = StreamableHTTPSessionManager(
            app=self._server._mcp_server,
            json_response=True,
            stateless=True,
            # DNS-rebinding protection is for servers reached by browsers that
            # trust the network they are on; this one is reached by name from
            # anywhere, and authenticates every request with a bearer key (no
            # cookies for a rebinding page to ride on).
            security_settings=TransportSecuritySettings(enable_dns_rebinding_protection=False),
        )
        async with manager.run():
            self._manager = manager
            try:
                yield
            finally:
                self._manager = None

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":  # pragma: no cover - lifespan etc. never reach a route
            return
        authorization = Headers(scope=scope).get("authorization", "")
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not looks_like_api_key(token.strip()):
            await self._reject(
                scope,
                receive,
                send,
                "send an API key (Settings > API keys) as `Authorization: Bearer dnk_...`; "
                "passwords and login tokens are not accepted here",
            )
            return
        app: ASGIApp = scope["app"]
        caller = _Caller(app=app, authorization=f"Bearer {token.strip()}")
        reset = _caller.set(caller)
        try:
            # Reject a bad key now, at connection time, not on the first tool call.
            await self._check_key(caller)
        except McpApiError:
            _caller.reset(reset)
            await self._reject(scope, receive, send, "invalid API key")
            return
        try:
            if self._manager is None:
                response = JSONResponse(
                    {"detail": "the MCP server is starting up"}, status_code=503
                )
                await response(scope, receive, send)
                return
            await self._manager.handle_request(scope, receive, send)
        finally:
            _caller.reset(reset)

    @staticmethod
    async def _check_key(caller: _Caller) -> None:
        async with httpx2.AsyncClient(
            transport=httpx2.ASGITransport(app=caller.app),
            base_url="http://dinatos.internal",
            headers={"Authorization": caller.authorization},
        ) as client:
            response = await client.get("/profile")
        if response.status_code != httpx2.codes.OK:
            raise McpApiError(str(response.status_code))

    @staticmethod
    async def _reject(scope: Scope, receive: Receive, send: Send, detail: str) -> None:
        response = JSONResponse(
            {"detail": detail}, status_code=401, headers={"WWW-Authenticate": "Bearer"}
        )
        await response(scope, receive, send)


# One per process: the MCP endpoint mounted at `/mcp` (see `main.py`), started and
# stopped with the app's lifespan.
mcp_gateway = McpGateway()
