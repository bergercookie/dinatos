#!/usr/bin/env bash
# Installs a built .deb into a pristine container of the *oldest* Ubuntu we
# support and checks it actually runs there -- a package built on a newer
# distro silently requires that distro's glibc (e.g. `GLIBC_2.38 not found`
# on 22.04), which nothing on the build machine itself can reveal.
#
# usage: smoke-test-deb.sh <path-to.deb> [image]   (needs Docker)
set -euo pipefail

DEB="$(realpath "${1:?usage: smoke-test-deb.sh <path-to.deb> [image]}")"
IMAGE="${2:-ubuntu:22.04}"

docker run --rm -v "${DEB}:/pkg/dinatos.deb:ro" "${IMAGE}" bash -euo pipefail -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # xvfb + software GL: the app needs *a* display to start, not a real one.
  apt-get install -y -qq /pkg/dinatos.deb xvfb libgl1-mesa-dri libegl1 >/dev/null

  # Every shared object must resolve and fit this distro'\''s glibc: the
  # dynamic loader reports an unmet GLIBC_x.y requirement as "not found".
  #
  # One exemption: libdartjni.so (the `jni` package'\''s native hook) links
  # libjvm.so, which only a JDK provides. Nothing on desktop calls into JNI --
  # it is Android plumbing that rides along in the bundle -- so the library is
  # never loaded and a missing JVM is not a defect of the package.
  missing=0
  for f in /usr/lib/dinatos/dinatos_frontend /usr/lib/dinatos/lib/*.so; do
    out="$(ldd "$f" 2>&1 | grep -E "not found|version .* not found" || true)"
    if [ "$(basename "$f")" = libdartjni.so ]; then
      out="$(printf "%s" "$out" | grep -v "libjvm.so" || true)"
    fi
    if [ -n "$out" ]; then
      echo "FAIL: $f"; echo "$out"; missing=1
    fi
  done
  [ "$missing" -eq 0 ] || exit 1

  # Launch it: still alive after 10s (timeout exits 124) means it started.
  rc=0
  timeout 10 xvfb-run -a dinatos || rc=$?
  if [ "$rc" -ne 124 ]; then
    echo "FAIL: dinatos exited early with status $rc" >&2
    exit 1
  fi
  echo "OK: dinatos installs and starts on '"${IMAGE}"'"
'
