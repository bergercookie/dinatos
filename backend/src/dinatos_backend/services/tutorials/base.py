"""The contract every tutorial provider implements, and the shared shape
their results come back in -- regardless of which one is active (see
`services.tutorials.get_tutorial_provider_for_key`), an exercise's tutorial always
looks the same to the rest of the app.
"""

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class ExerciseTutorial:
    source: str
    gif_urls: list[str]
    instructions: list[str]
    equipment: str | None
    primary_muscles: list[str]
    secondary_muscles: list[str]


class TutorialProvider(Protocol):
    async def get_tutorial(self, exercise_name: str) -> ExerciseTutorial | None:
        """The tutorial for an exercise by (exact, case-insensitive) name,
        or `None` if this provider has nothing for it -- never raised as
        an error, since "no tutorial" is an expected, ordinary outcome,
        not a failure. A provider *may* raise for an actual failure to
        reach it (a network error, a non-2xx response) -- callers decide
        how to surface that.
        """
        ...
