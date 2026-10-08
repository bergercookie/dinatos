# Three stages: build the Flutter web app, resolve backend dependencies with
# uv, then ship a plain Python runtime containing nothing but the venv and
# the web build -- one self-contained image with everything a homelab user
# needs to point a browser at. Build context is the repo root (not
# backend/), since this needs frontend/ too.

FROM python:3.12-slim-trixie AS frontend-builder

# Flutter's own release archive is a full git checkout (an embedded `.git`
# the `flutter`/`dart` tools shell out to for their own version banner) --
# without git installed, every invocation below fails outright, not just
# `flutter --version`. Unpinned versions, deliberately, unlike UV_VERSION
# below (this project's own dependency): these are base-OS packages, and
# letting `apt-get` resolve whatever `trixie` currently has means picking up
# Debian's own security patches for them, which a version pinned here would
# instead need bumping by hand to get.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
    && rm -rf /var/lib/apt/lists/*

# No pinned version here, deliberately: unlike UV_VERSION below, this
# project already tracks Flutter's `stable` channel with no pin anywhere
# (`.github/workflows/release.yml`'s android-apk/linux-packages jobs and
# ci.yml's frontend/screenshots jobs all use `subosito/flutter-action@v2`
# with `channel: stable`, no `flutter-version:`) -- pinning an exact archive
# here would just be a second, easily-drifting source of truth for the same
# thing. This asks Google's own releases feed which Linux archive `stable`
# currently points to and downloads exactly that -- the same approach
# AGENTS.md recommends for a fresh unattended container, made reproducible
# enough for a build step by resolving it once, right before it's used.
RUN curl -fsSL -o /tmp/releases.json \
        https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
    && archive=$(python3 -c "import json; d = json.load(open('/tmp/releases.json')); h = d['current_release']['stable']; print(next(r['archive'] for r in d['releases'] if r['hash'] == h))") \
    && curl -fsSL -o /tmp/flutter.tar.xz \
        "https://storage.googleapis.com/flutter_infra_release/releases/${archive}" \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz /tmp/releases.json

ENV PATH="/opt/flutter/bin:${PATH}"
# Building as root (this stage's default user): the harmless "Woah! You
# appear to be trying to run flutter as root" banner is expected here, see
# AGENTS.md. `safe.directory` avoids a separate "detected dubious
# ownership" git error root would otherwise hit against the extracted SDK.
RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics \
    && dart --disable-analytics \
    && flutter precache --web

WORKDIR /app
# Dependencies first, so editing app source doesn't invalidate this layer.
COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get

COPY frontend .
# No --dart-define=API_BASE_URL here, deliberately: this build is served by
# the backend itself at runtime (see the runtime stage and `main.py`'s
# `_WebApp`), and `ApiConfig`'s default for a web build with no override is
# already "whatever origin served it" -- same-origin, zero setup. See
# docs/deploy/clients.md for building against a separately-hosted backend.
ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown
RUN flutter build web --release \
    --dart-define=APP_VERSION="${APP_VERSION}" \
    --dart-define=GIT_COMMIT="${GIT_COMMIT}"


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
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

# alembic.ini + alembic/ are needed at runtime too (migrations run on
# container start, see docker-entrypoint.sh), not just to build the package.
COPY backend/alembic.ini ./
COPY backend/alembic ./alembic
COPY backend/src ./src

# Stamp the release version into the package itself (it is otherwise the
# hard-coded one in pyproject.toml, so every nightly/release reported
# 0.1.0 from the API, its OpenAPI document and the backups). The release
# version is not always PEP 440 -- a nightly is `<base>-nightly.YYYYMMDD[.N]`
# -- so that form becomes `<base>.devYYYYMMDD[N]`; a plain `dev` (an unset
# build arg) leaves pyproject.toml's own version alone.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG APP_VERSION=dev
RUN if [ "${APP_VERSION}" != dev ]; then \
        py_version="$(printf '%s' "${APP_VERSION}" | sed -E 's/-nightly\.([0-9]+)(\.([0-9]+))?$/.dev\1\3/')" \
        && sed -i -E "0,/^version = \".*\"/s//version = \"${py_version}\"/" pyproject.toml \
        && grep -m1 '^version = ' pyproject.toml; \
    fi

# --no-editable installs a real wheel, so the runtime stage needs the
# virtualenv and nothing else -- without it, `uv sync`'s default editable
# install leaves the venv pointing back at /app/src *in this stage*, which
# does not exist once only .venv/ is copied into runtime below.
#
# --frozen, not --locked, for this one: the stamp above changes the project's
# own version, which --locked would reject as a stale uv.lock (the dependency
# set it checks was already verified by the --locked sync further up).
RUN uv sync --frozen --no-dev --no-editable


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
COPY --chown=dinatos:dinatos backend/pyproject.toml backend/alembic.ini ./
COPY --chown=dinatos:dinatos backend/alembic ./alembic
COPY --chown=dinatos:dinatos backend/docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh
# `Settings.web_dir` (backend/src/dinatos_backend/config.py) defaults to
# exactly this relative path, resolved against the process's working
# directory -- WORKDIR above -- so main.py finds and serves it with no
# further configuration needed.
COPY --from=frontend-builder --chown=dinatos:dinatos /app/build/web ./web

# Numeric, not the name: resolvable even without /etc/passwd, and makes it
# unambiguous at a glance that this isn't 0/root.
USER ${APP_UID}:${APP_GID}
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4)"]

ENTRYPOINT ["./docker-entrypoint.sh"]
