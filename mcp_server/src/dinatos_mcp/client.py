"""A thin async client for the Dinatos REST API.

Talks to a running backend instance over HTTP, the same as the Flutter app
or a `curl` script would -- see docs/architecture/backend.md's
"Authentication" section for why the token is an opaque, revocable session
rather than a self-verifying JWT.
"""

import asyncio
from datetime import datetime
from typing import Any

import httpx

from dinatos_mcp.config import Settings
from dinatos_mcp.schemas import ActivityExerciseInput, WorkoutExerciseInput


class DinatosConfigError(RuntimeError):
    """No usable credentials -- neither a token nor an email/password pair."""


class DinatosAPIError(RuntimeError):
    """The backend answered with an error status; `detail` is its response body's
    `detail` field (FastAPI's `HTTPException` shape) when present, else the
    raw response text.
    """

    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(f"{status_code}: {detail}")
        self.status_code = status_code
        self.detail = detail


def _error_detail(response: httpx.Response) -> str:
    try:
        body = response.json()
    except ValueError:
        return response.text
    detail = body.get("detail") if isinstance(body, dict) else None
    return str(detail) if detail is not None else response.text


class DinatosClient:
    """One instance per MCP server process -- logs in at most once, lazily,
    the first time a request needs a token it doesn't already have.
    """

    def __init__(
        self, http: httpx.AsyncClient, *, email: str | None = None, password: str | None = None
    ) -> None:
        self._http = http
        self._email = email
        self._password = password
        self._login_lock = asyncio.Lock()

    @property
    def http(self) -> httpx.AsyncClient:
        """The underlying httpx client -- exposed for tests asserting on
        `base_url`/`headers`, not meant for routine use (use the typed
        methods below instead).
        """
        return self._http

    @classmethod
    def from_settings(cls, settings: Settings) -> "DinatosClient":
        http = httpx.AsyncClient(base_url=settings.base_url, timeout=30.0)
        if settings.token:
            http.headers["Authorization"] = f"Bearer {settings.token}"
        return cls(http, email=settings.email, password=settings.password)

    async def aclose(self) -> None:
        await self._http.aclose()

    async def _ensure_authenticated(self) -> None:
        if "Authorization" in self._http.headers:
            return
        if not (self._email and self._password):
            raise DinatosConfigError(
                "no Dinatos credentials configured -- set DINATOS_MCP_TOKEN, or both "
                "DINATOS_MCP_EMAIL and DINATOS_MCP_PASSWORD"
            )
        async with self._login_lock:
            if "Authorization" in self._http.headers:
                return  # a concurrent call won the race and already logged in
            response = await self._http.post(
                "/auth/login", json={"email": self._email, "password": self._password}
            )
            if response.status_code != httpx.codes.OK:
                raise DinatosAPIError(response.status_code, _error_detail(response))
            self._http.headers["Authorization"] = f"Bearer {response.json()['access_token']}"

    async def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        # Every call this client makes gets either an error or a JSON body
        # back -- nothing here ever hits a 204 No Content endpoint (no
        # delete/logout tool is exposed), so there's no branch for one.
        await self._ensure_authenticated()
        response = await self._http.request(method, path, **kwargs)
        if response.status_code >= httpx.codes.BAD_REQUEST:
            raise DinatosAPIError(response.status_code, _error_detail(response))
        return response.json()

    async def list_exercises(self, search: str | None = None) -> list[dict[str, Any]]:
        params = {"search": search} if search else None
        result: list[dict[str, Any]] = await self._request("GET", "/exercises", params=params)
        return result

    async def create_exercise(
        self,
        name: str,
        *,
        tracks_weight: bool = True,
        tracks_reps: bool = True,
        tracks_distance: bool = False,
        tracks_duration: bool = False,
    ) -> dict[str, Any]:
        payload = {
            "name": name,
            "tracks_weight": tracks_weight,
            "tracks_reps": tracks_reps,
            "tracks_distance": tracks_distance,
            "tracks_duration": tracks_duration,
        }
        result: dict[str, Any] = await self._request("POST", "/exercises", json=payload)
        return result

    async def list_workouts(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = await self._request("GET", "/workouts")
        return result

    async def create_workout(
        self,
        name: str,
        exercises: list[WorkoutExerciseInput],
        *,
        description: str | None = None,
    ) -> dict[str, Any]:
        payload = {
            "name": name,
            "description": description,
            "exercises": [item.model_dump(mode="json") for item in exercises],
        }
        result: dict[str, Any] = await self._request("POST", "/workouts", json=payload)
        return result

    async def list_activities(
        self, since: datetime | None = None, until: datetime | None = None
    ) -> list[dict[str, Any]]:
        params = {
            key: value.isoformat()
            for key, value in {"since": since, "until": until}.items()
            if value is not None
        }
        result: list[dict[str, Any]] = await self._request(
            "GET", "/activities", params=params or None
        )
        return result

    async def log_activity(
        self,
        title: str,
        started_at: datetime,
        exercises: list[ActivityExerciseInput],
        *,
        description: str | None = None,
        ended_at: datetime | None = None,
        workout_id: int | None = None,
    ) -> dict[str, Any]:
        payload = {
            "title": title,
            "description": description,
            "started_at": started_at.isoformat(),
            "ended_at": ended_at.isoformat() if ended_at is not None else None,
            "workout_id": workout_id,
            "exercises": [item.model_dump(mode="json") for item in exercises],
        }
        result: dict[str, Any] = await self._request("POST", "/activities", json=payload)
        return result
