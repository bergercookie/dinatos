# `free_exercise_db.json`

Vendored from <https://github.com/yuhonas/free-exercise-db>, commit
`f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5` (`dist/exercises.json`).

Released into the public domain under the [Unlicense](https://unlicense.org/)
-- see that repository's `LICENSE.md`. No attribution is legally required,
but this file exists so a future update knows exactly what was vendored and
from where.

The exercise images this file's `images` field points at are **not**
vendored here (105MB, and only 2 static JPGs per exercise, not the "GIF" the
project's name suggests) -- `services/tutorials/free_exercise_db.py` builds
their URLs by prefixing `raw.githubusercontent.com` at request time instead.
Re-vendor this file (and reconsider mirroring the images) if that upstream
repository ever disappears or changes its license.
