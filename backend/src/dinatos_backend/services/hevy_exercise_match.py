"""Best-effort mapping of Hevy's built-in exercise names to the seeded catalog.

Hevy names exercises "Movement (Equipment)" ("Bench Press (Barbell)"), while
the seeded catalog (`data/free_exercise_db.json`) uses its own spelling
("Barbell Bench Press - Medium Grip"), so an exact-name lookup almost never
hits and every import would create a duplicate of an exercise we already
have. Matching goes, in order:

1. a curated alias table for the common Hevy built-ins whose catalog
   spelling differs in more than word order (`_ALIASES`);
2. a word-order-insensitive comparison of the two names' words, with the
   equipment suffix folded in ("Bicep Curl (Dumbbell)" == "Dumbbell Bicep
   Curl"), accepted only if exactly one catalog exercise has those words.

Anything that doesn't match -- notably every custom Hevy exercise -- simply
isn't matched, and the caller creates it as before. Only the shipped
(`is_custom=False`) catalog is ever matched fuzzily; a person's own
exercises are only found by exact name.
"""

import re

from dinatos_backend.models.exercise import Exercise

# Lowercased Hevy title -> exact catalog name. Every target must exist in the
# vendored dataset (enforced by tests/services/test_hevy_exercise_match.py).
_ALIASES: dict[str, str] = {
    "bench press (barbell)": "Barbell Bench Press - Medium Grip",
    "incline bench press (barbell)": "Barbell Incline Bench Press - Medium Grip",
    "decline bench press (barbell)": "Decline Barbell Bench Press",
    "romanian deadlift (barbell)": "Romanian Deadlift",
    "sumo deadlift (barbell)": "Sumo Deadlift",
    "rack pull (barbell)": "Rack Pulls",
    "good morning (barbell)": "Good Morning",
    "front squat (barbell)": "Front Barbell Squat",
    "hack squat (machine)": "Hack Squat",
    "goblet squat (kettlebell)": "Goblet Squat",
    "goblet squat (dumbbell)": "Goblet Squat",
    "overhead press (barbell)": "Standing Military Press",
    "seated overhead press (barbell)": "Seated Barbell Military Press",
    "overhead press (dumbbell)": "Dumbbell Shoulder Press",
    "shoulder press (smith machine)": "Smith Machine Overhead Shoulder Press",
    "arnold press (dumbbell)": "Arnold Dumbbell Press",
    "upright row (barbell)": "Upright Barbell Row",
    "lateral raise (dumbbell)": "Side Lateral Raise",
    "bicep curl (barbell)": "Barbell Curl",
    "ez bar biceps curl": "EZ-Bar Curl",
    "hammer curl (dumbbell)": "Hammer Curls",
    "preacher curl (machine)": "Machine Preacher Curls",
    "triceps pushdown": "Triceps Pushdown",
    "triceps pushdown (cable)": "Triceps Pushdown",
    "triceps rope pushdown": "Triceps Pushdown - Rope Attachment",
    "skullcrusher (barbell)": "EZ-Bar Skullcrusher",
    "lat pulldown (cable)": "Wide-Grip Lat Pulldown",
    "pull up": "Pullups",
    "chin up": "Chin-Up",
    "push up": "Pushups",
    "seated row (cable)": "Seated Cable Rows",
    "bent over row (barbell)": "Bent Over Barbell Row",
    "bent over row (dumbbell)": "Bent Over Two-Dumbbell Row",
    "dumbbell row": "One-Arm Dumbbell Row",
    "t bar row": "T-Bar Row with Handle",
    "leg press (machine)": "Leg Press",
    "leg extension (machine)": "Leg Extensions",
    "seated leg curl (machine)": "Seated Leg Curl",
    "lying leg curl (machine)": "Lying Leg Curls",
    "standing calf raise (machine)": "Standing Calf Raises",
    "seated calf raise (machine)": "Seated Calf Raise",
    "calf press (machine)": "Calf Press",
    "rear delt reverse fly (cable)": "Cable Rear Delt Fly",
    "butterfly (pec deck)": "Butterfly",
    "chest fly (dumbbell)": "Dumbbell Flyes",
    "incline chest fly (dumbbell)": "Incline Dumbbell Flyes",
    "chest dip": "Dips - Chest Version",
    "triceps dip": "Dips - Triceps Version",
    "bench dip": "Bench Dips",
    "crunch": "Crunches",
    "treadmill": "Running, Treadmill",
    "running (treadmill)": "Running, Treadmill",
    "rowing machine": "Rowing, Stationary",
    "skipping": "Rope Jumping",
    "incline bench press (dumbbell)": "Incline Dumbbell Press",
    "chest press (machine)": "Leverage Chest Press",
    "incline chest press (machine)": "Leverage Incline Chest Press",
    "back extension (machine)": "Hyperextensions (Back Extensions)",
    "back extension (weighted hyperextension)": "Hyperextensions (Back Extensions)",
    "band pullaparts": "Band Pull Apart",
    "cable fly crossovers": "Cable Crossover",
    "cable pull through": "Pull Through",
    "pull up (assisted)": "Band Assisted Pull-Up",
    "crunch (machine)": "Ab Crunch Machine",
    "farmers walk": "Farmer's Walk",
    "front squat": "Front Squat (Clean Grip)",
    "glute kickback (machine)": "Glute Kickback",
    "kettlebell goblet squat": "Goblet Squat",
    "hammer curl (cable)": "Cable Hammer Curls - Rope Attachment",
    "hip abduction (machine)": "Thigh Abductor",
    "hip adduction (machine)": "Thigh Adductor",
    "lateral raise (band)": "Lateral Raise - With Bands",
    "lying leg raise": "Flat Bench Lying Leg Raise",
    "overhead press (smith machine)": "Smith Machine Overhead Shoulder Press",
    "overhead triceps extension (cable)": "Cable Rope Overhead Triceps Extension",
    "scapular pull ups": "Scapular Pull-Up",
    "seated cable row - v grip (cable)": "Seated Cable Rows",
    "seated incline curl (dumbbell)": "Incline Dumbbell Curl",
    "shoulder press (machine plates)": "Machine Shoulder (Military) Press",
    "single arm tricep extension (dumbbell)": "Dumbbell One-Arm Triceps Extension",
    "spinning": "Bicycling, Stationary",
    "standing calf raise (smith)": "Smith Machine Calf Raise",
    "straight arm lat pulldown (cable)": "Straight-Arm Pulldown",
}

# Words that carry no movement information once the equipment is folded in:
# Hevy's "(Bodyweight)" suffix, and the catalog's "Bodyweight X" prefix.
_IGNORED_WORDS = frozenset({"bodyweight"})


def _words(name: str) -> frozenset[str]:
    out: set[str] = set()
    for word in re.split(r"[^a-z0-9]+", name.lower()):
        if not word or word in _IGNORED_WORDS:
            continue
        # Crude plural fold ("Lunges"/"Lunge", "Kettlebells"/"Kettlebell").
        if len(word) > 3 and word.endswith("s") and not word.endswith("ss"):
            word = word[:-1]
        out.add(word)
    return frozenset(out)


_COMPOUND_RE = re.compile(r"\b(pull|push|chin|sit)[\s-]+ups?\b")


def words_of(name: str) -> frozenset[str]:
    """`_words`, plus joining "Pull Up"/"Pull-Ups"/"Pullups" into one word --
    for *similarity* comparisons (`hevy_exercise_infer`), where those
    spellings must look alike. The exact matcher below keeps `_words`."""
    return _words(_COMPOUND_RE.sub(r"\1up", name.lower()))


class CatalogMatcher:
    """Built once per import from the seeded (non-custom) exercises."""

    def __init__(self, catalog: list[Exercise]) -> None:
        self._by_lower_name = {exercise.name.lower(): exercise for exercise in catalog}
        by_words: dict[frozenset[str], list[Exercise]] = {}
        for exercise in catalog:
            by_words.setdefault(_words(exercise.name), []).append(exercise)
        # Ambiguous word sets (two catalog entries identical up to word
        # order/plurals) are dropped rather than guessed at.
        self._by_words = {words: found[0] for words, found in by_words.items() if len(found) == 1}

    def match(self, hevy_name: str) -> Exercise | None:
        key = hevy_name.strip().lower()
        if key in self._by_lower_name:
            return self._by_lower_name[key]
        alias = _ALIASES.get(key)
        if alias is not None:
            return self._by_lower_name.get(alias.lower())
        words = _words(hevy_name)
        return self._by_words.get(words) if words else None
