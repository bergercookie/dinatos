#!/usr/bin/env bash
# Runs inside Dockerfile.build's image: builds the Linux packages from a *copy*
# of the repo mounted read-only at /src, and writes them to /out.
#
# A copy, not a build in place: the host checkout's frontend/build,
# .dart_tool and linux/flutter/ephemeral hold absolute host paths and
# whatever toolchain built them (CMakeCache.txt especially), and reusing
# them in here fails confusingly -- or worse, silently links the wrong libs.
#
# Env: VERSION (required), RECIPE (a packaging/justfile recipe: build-deb,
# build-appimage or build-linux-artifacts; default the last), HOST_UID /
# HOST_GID (owner of the output files).
set -euo pipefail

: "${VERSION:?VERSION is required}"

rsync -a \
  --exclude '.devbox/' \
  --exclude 'dist/' \
  --exclude 'backend/.venv/' \
  --exclude 'frontend/build/' \
  --exclude 'frontend/.dart_tool/' \
  --exclude 'frontend/.flutter-plugins-dependencies' \
  --exclude 'frontend/linux/flutter/ephemeral/' \
  /src/ /work/

cd /work/packaging
just "${RECIPE:-build-linux-artifacts}" "${VERSION}" dist

cp /work/dist/* /out/
chown "${HOST_UID:-0}:${HOST_GID:-0}" /out/*
