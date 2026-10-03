#!/usr/bin/env bash
# Packages an already-built `flutter build linux --release` bundle
# (frontend/build/linux/x64/release/bundle) as a .deb -- run that build
# first. The packaging module's `build-deb` and `build-linux-artifacts`
# recipes run that build before calling this lower-level packaging script.
#
# The bundle's own binary already has its rpath set to `$ORIGIN/lib`
# (flutter build linux's own CMake install step does this), so installing
# it whole under /usr/lib/dinatos/ with its lib/ and data/ siblings intact
# is what makes that keep resolving after packaging -- don't split those
# apart.
set -euo pipefail

VERSION="${1:?usage: build-deb.sh <version> <output-dir>}"
OUTPUT_DIR="${2:?usage: build-deb.sh <version> <output-dir>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUNDLE_DIR="${REPO_ROOT}/frontend/build/linux/x64/release/bundle"
PKG_NAME="dinatos"
ARCH="amd64"

if [ ! -x "${BUNDLE_DIR}/dinatos_frontend" ]; then
  echo "error: ${BUNDLE_DIR}/dinatos_frontend not found -- run" \
    "'flutter build linux --release' in frontend/ first" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

install -d "${STAGE}/DEBIAN"
install -d "${STAGE}/usr/lib/${PKG_NAME}"
install -d "${STAGE}/usr/bin"
install -d "${STAGE}/usr/share/applications"
install -d "${STAGE}/usr/share/icons/hicolor/512x512/apps"

cp -r "${BUNDLE_DIR}/." "${STAGE}/usr/lib/${PKG_NAME}/"
ln -s "/usr/lib/${PKG_NAME}/dinatos_frontend" "${STAGE}/usr/bin/${PKG_NAME}"
install -m 644 "${SCRIPT_DIR}/dinatos.desktop" "${STAGE}/usr/share/applications/dinatos.desktop"
install -m 644 "${REPO_ROOT}/frontend/web/icons/Icon-512.png" \
  "${STAGE}/usr/share/icons/hicolor/512x512/apps/dinatos.png"

# Debian wants this in the control file, not just accurate on disk.
INSTALLED_SIZE="$(du -sk "${STAGE}/usr" | cut -f1)"

# libgtk-3-0/libsecret-1-0: what the bundle actually links against beyond
# the C library (see `ldd` on the built binary) -- flutter's own engine
# and app code (libflutter_linux_gtk.so, libapp.so) are bundled in lib/
# next to the binary, not system-installed, so they aren't Depends here.
cat >"${STAGE}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: contrib/misc
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libsecret-1-0
Maintainer: Dinatos contributors <https://github.com/bergercookie/dinatos>
Description: Self-hosted workout tracker
 Dinatos is a self-hosted workout tracker: exercises, routines, and the
 activities you log against them. This is the Linux desktop client; it
 talks to a Dinatos backend you run yourself (see the Server field on
 first launch).
EOF

mkdir -p "${OUTPUT_DIR}"
OUT_FILE="${OUTPUT_DIR}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "${STAGE}" "${OUT_FILE}"
echo "Built ${OUT_FILE}"
