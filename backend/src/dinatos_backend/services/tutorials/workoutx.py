"""Optional tutorial provider: WorkoutX (https://workoutxapp.com), a paid
third-party API each user can opt into with their own account (see
`UserProfile.workoutx_api_key`) instead of the bundled
`free-exercise-db` dataset -- its chief advantage over that dataset is
real animated GIFs rather than two static JPGs per exercise.

WorkoutX's own terms of service prohibit bulk caching or scraping their
dataset ("Scrape or cache exercise data in bulk beyond what is needed for
your application", "Redistribute the exercise dataset as a standalone
product"), so this only ever fetches one exercise at a time, on demand,
the moment someone actually opens its tutorial -- never a sync of their
whole catalog. `services.tutorials.cache.CachingTutorialProvider` (what
actually wraps this in production) keeps that same one-at-a-time shape in
memory rather than persisting it, both to stay inside that clause and per
this project's own choice not to persist third-party tutorial content at
all (see that module's docstring).

Failures here (a bad key, an outage) are not surfaced to the caller:
`services.tutorials.fallback.FallbackTutorialProvider` serves the bundled
dataset instead.
"""

import httpx2 as httpx

from dinatos_backend.services.tutorials.base import ExerciseTutorial

_BASE_URL = "https://api.workoutxapp.com/v1"


class WorkoutXProvider:
    def __init__(self, api_key: str, *, client: httpx.AsyncClient | None = None) -> None:
        # The key is sent per-request (not baked into `client` at
        # construction) so a caller-supplied `client` -- tests only, a
        # fake transport, no real network -- still gets it: `client`
        # otherwise bypasses whatever headers the default one would have
        # been built with.
        self._api_key = api_key
        self._client = client or httpx.AsyncClient(base_url=_BASE_URL, timeout=10.0)

    async def get_tutorial(self, exercise_name: str) -> ExerciseTutorial | None:
        response = await self._client.get(
            f"/exercises/name/{exercise_name}", headers={"X-WorkoutX-Key": self._api_key}
        )
        if response.status_code == httpx.codes.NOT_FOUND:
            return None
        response.raise_for_status()
        payload = response.json()
        # Their own docs show sibling endpoints ("Similar Exercises",
        # "Alternative Exercises") wrapping results as
        # {"total", "count", "data": [...]} rather than a bare array, and
        # in practice this endpoint does too, despite its own docs example
        # showing a bare array -- confirmed by a real `KeyError: 0` from
        # `matches[0]` below when `matches` was actually that dict.
        matches = payload.get("data", []) if isinstance(payload, dict) else payload
        if not matches:
            return None
        # The endpoint is a partial, case-insensitive name search, so an
        # exact match (once case-folded) among the results is preferred
        # over just taking whichever one it ranked first.
        entry = next(
            (match for match in matches if match["name"].casefold() == exercise_name.casefold()),
            matches[0],
        )
        return ExerciseTutorial(
            source="workoutx",
            gif_urls=[entry["gifUrl"]] if entry.get("gifUrl") else [],
            instructions=entry.get("instructions", []),
            equipment=entry.get("equipment"),
            primary_muscles=[entry["target"]] if entry.get("target") else [],
            secondary_muscles=entry.get("secondaryMuscles", []),
        )
