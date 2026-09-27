# Two stages: resolve dependencies with uv, then ship a plain Python runtime
# containing nothing but the virtualenv. Everything comes from one registry
# (Docker Hub) so this still builds behind a restrictive mirror or a proxy
# that only allows one upstream.

FROM python:3.12-slim-trixie AS builder

# Pinned so a rebuild resolves the same way; bump deliberately alongside uv.lock.
ARG UV_VERSION=0.8.17

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install --no-cache-dir "uv==${UV_VERSION}"

WORKDIR /app

# Dependencies first, so editing source does not invalidate this layer.
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

# alembic.ini + alembic/ are needed at runtime too (migrations run on
# container start, see docker-entrypoint.sh), not just to build the package.
COPY alembic.ini ./
COPY alembic ./alembic
COPY src ./src

# --no-editable installs a real wheel, so the runtime stage needs the
# virtualenv and nothing else -- without it, `uv sync`'s default editable
# install leaves the venv pointing back at /app/src *in this stage*, which
# does not exist once only .venv/ is copied into runtime below.
RUN uv sync --locked --no-dev --no-editable


FROM python:3.12-slim-trixie AS runtime

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

# Nothing in this image runs as root.
ARG APP_UID=10001
ARG APP_GID=10001
RUN groupadd --system --gid "${APP_GID}" dinatos \
    && useradd --system --create-home --uid "${APP_UID}" --gid "${APP_GID}" dinatos

WORKDIR /app
COPY --from=builder --chown=dinatos:dinatos /app/.venv /app/.venv
# Alembic auto-detects pyproject.toml (for [tool.alembic]) and alembic.ini
# (for logging) in the current directory -- both have to be here, not just
# alembic/versions/, for `alembic upgrade head` to run at all.
COPY --chown=dinatos:dinatos pyproject.toml alembic.ini ./
COPY --chown=dinatos:dinatos alembic ./alembic
COPY --chown=dinatos:dinatos docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# Numeric, not the name: resolvable even without /etc/passwd, and makes it
# unambiguous at a glance that this isn't 0/root.
USER ${APP_UID}:${APP_GID}
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4)"]

ENTRYPOINT ["./docker-entrypoint.sh"]
