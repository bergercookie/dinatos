"""Alembic migration checks, via pytest-alembic's built-in test suite, run
against a real (throwaway, testcontainers) Postgres -- not sqlite, since the
bug that motivated this suite (a Postgres ENUM type left behind by
`downgrade()`, breaking the next `upgrade()`) is invisible to a backend with
no `CREATE TYPE` to forget to undo in the first place.

- `test_single_head_revision` -- the history hasn't branched.
- `test_upgrade` -- base -> head runs cleanly.
- `test_model_definitions_match_ddl` -- the models and the migrations agree;
  an `alembic revision --autogenerate` right now would generate nothing.
- `test_up_down_consistency` -- every migration, individually: upgraded to,
  then downgraded, in reverse order, then upgraded again. This is how the
  ENUM bug was actually found, and is what a hand-rolled version of this
  suite used to do explicitly; pytest-alembic's version subsumes it.
"""

from pytest_alembic import tests
from pytest_alembic.runner import MigrationContext


def test_single_head_revision(alembic_runner: MigrationContext) -> None:
    tests.test_single_head_revision(alembic_runner)


def test_upgrade(alembic_runner: MigrationContext) -> None:
    tests.test_upgrade(alembic_runner)


def test_model_definitions_match_ddl(alembic_runner: MigrationContext) -> None:
    tests.test_model_definitions_match_ddl(alembic_runner)


def test_up_down_consistency(alembic_runner: MigrationContext) -> None:
    tests.test_up_down_consistency(alembic_runner)
