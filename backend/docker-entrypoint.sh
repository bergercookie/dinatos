#!/bin/sh
# Migrate then serve. `exec` hands off PID 1 to uvicorn so it receives
# SIGTERM directly and shuts down gracefully instead of dying with the shell.
set -e

alembic upgrade head
exec uvicorn dinatos_backend.main:app --host 0.0.0.0 --port 8000
