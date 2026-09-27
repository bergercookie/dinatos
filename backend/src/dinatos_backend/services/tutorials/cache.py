"""In-memory response cache for whichever `TutorialProvider` is active.

Deliberately process-lifetime only, never persisted to the database:
`workoutx.py`'s terms of service prohibit bulk-caching its data, and this
project's own choice (over a persistent `exercise_tutorials` table that
was considered and rejected) is that a restart re-fetches from the source
rather than reconciling stale cached content or a schema for someone
else's data. A restart pays for the first view of each exercise again;
every view after that, in the same process, doesn't.
"""

from dinatos_backend.services.tutorials.base import ExerciseTutorial, TutorialProvider


class CachingTutorialProvider:
    def __init__(self, provider: TutorialProvider) -> None:
        self._provider = provider
        self._cache: dict[str, ExerciseTutorial | None] = {}

    async def get_tutorial(self, exercise_name: str) -> ExerciseTutorial | None:
        key = exercise_name.casefold()
        if key not in self._cache:
            self._cache[key] = await self._provider.get_tutorial(exercise_name)
        return self._cache[key]
