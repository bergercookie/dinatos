#!/usr/bin/env bash
# Packages an already-built `flutter build linux --release` bundle
# (frontend/build/linux/x64/release/bundle) as a portable .AppImage -- run
# that build first. The packaging module's `build-appimage` and
# `build-linux-artifacts` recipes do so before calling this script. See
# build-deb.sh's header for why the bundle has to stay whole (binary + its
# own lib/ + data/ siblings, not split apart): same reasoning applies to
# the AppDir layout below.
set -euo pipefail

VERSION="${1:?usage: build-appimage.sh <version> <output-dir>}"
OUTPUT_DIR="${2:?usage: build-appimage.sh <version> <output-dir>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUNDLE_DIR="${REPO_ROOT}/frontend/build/linux/x64/release/bundle"
PKG_NAME="dinatos"

if [ ! -x "${BUNDLE_DIR}/dinatos_frontend" ]; then
  echo "error: ${BUNDLE_DIR}/dinatos_frontend not found -- run" \
    "'flutter build linux --release' in frontend/ first" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
APPDIR="${WORK_DIR}/Dinatos.AppDir"

install -d "${APPDIR}/usr/bin"
cp -r "${BUNDLE_DIR}/." "${APPDIR}/usr/bin/"
install -m 644 "${REPO_ROOT}/frontend/web/icons/Icon-512.png" "${APPDIR}/dinatos.png"

# appimagetool wants Exec/Icon/a desktop file at the AppDir root; Exec here
# is relative to AppRun below, not a system PATH lookup.
cat >"${APPDIR}/dinatos.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Dinatos
Comment=Self-hosted workout tracker
Exec=dinatos_frontend
Icon=dinatos
Categories=Utility;
Terminal=false
EOF

# $(dirname "$(readlink -f ...)") rather than a plain relative cd, so this
# still finds usr/bin/ (and, through the binary's own $ORIGIN/lib rpath,
# its bundled libraries) regardless of the caller's own working directory
# or however the AppImage's own runtime chose to invoke this.
cat >"${APPDIR}/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "${0}")")"
exec "${HERE}/usr/bin/dinatos_frontend" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

# Pinned to the AppImage project's own "continuous" build, its documented
# way to fetch appimagetool in CI -- there hasn't been a numbered
# appimagetool release since 2020, so continuous is the only moving
# target that stays current with e.g. glibc compatibility fixes.
APPIMAGETOOL="${WORK_DIR}/appimagetool.AppImage"
curl -fsSL --retry 3 -o "${APPIMAGETOOL}" \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x "${APPIMAGETOOL}"

mkdir -p "${OUTPUT_DIR}"
OUT_FILE="${OUTPUT_DIR}/${PKG_NAME}-${VERSION}-x86_64.AppImage"
# --appimage-extract-and-run: this and the AppDir it's building both need
# FUSE to mount themselves the "normal" way, which most CI runners and
# containers don't have available; extracting and running avoids needing
# it for either.
"${APPIMAGETOOL}" --appimage-extract-and-run "${APPDIR}" "${OUT_FILE}"
echo "Built ${OUT_FILE}"
