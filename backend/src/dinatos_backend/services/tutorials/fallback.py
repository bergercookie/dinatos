"""Wraps an opt-in provider (WorkoutX) so it can never make things worse
than not having opted in: if it fails, or simply has nothing for an
exercise, the always-available bundled provider answers instead.
"""

import logging

from dinatos_backend.services.tutorials.base import ExerciseTutorial, TutorialProvider

logger = logging.getLogger(__name__)


class FallbackTutorialProvider:
    def __init__(self, primary: TutorialProvider, fallback: TutorialProvider) -> None:
        self._primary = primary
        self._fallback = fallback

    async def get_tutorial(self, exercise_name: str) -> ExerciseTutorial | None:
        try:
            tutorial = await self._primary.get_tutorial(exercise_name)
        except Exception:
            # Deliberately broad, for the same reason as the tutorial
            # router's own catch: a bad key (401), a quota/rate limit, an
            # outage, or a malformed body are all "primary unusable", and
            # the fix for every one of them is the same -- keep serving
            # the bundled dataset rather than a 502.
            logger.warning(
                "primary tutorial provider failed for %r; falling back",
                exercise_name,
                exc_info=True,
            )
            return await self._fallback.get_tutorial(exercise_name)
        if tutorial is None:
            return await self._fallback.get_tutorial(exercise_name)
        return tutorial
