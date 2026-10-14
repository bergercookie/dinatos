# Distribution

How a Dinatos release is built and published: the Docker image, the Linux
packages and the Android APK. For contributors touching packaging, the
Dockerfile or `release.yml`. Workflow-level details (CI jobs, nightlies, the
release checklist) are in [CI and releases](../development/ci-and-releases.md).

## What a release produces

Pushing a tag matching `v*` (e.g. `v1.2.3`) runs `.github/workflows/release.yml`.
Its jobs run in parallel:

| Artifact | Built by | Notes |
| --- | --- | --- |
| Docker image (backend plus built web app) | root `Dockerfile` | Pushed to `ghcr.io/<owner>/dinatos`, tagged with the version and `latest`. `linux/amd64` only; the workflow comments say what `arm64` would need. |
| Linux `.deb` | `packaging/linux/build-deb.sh` | From the same `flutter build linux --release` bundle as the AppImage. |
| Linux `.AppImage` (portable) | `packaging/linux/build-appimage.sh` | Same bundle, so the two cannot drift. |
| Android APK | `just packaging build-apk` | Signed with the release key, see below. |

A `version` job strips the leading `v` from the tag once, so every artifact and
the GitHub Release share one version string (`dpkg-deb` rejects a leading `v`).
A final `release` job gathers everything into one GitHub Release.

The same workflow is also called by `nightly.yml` for prereleases (Docker tag
`nightly`, no `latest`).

**First push to GHCR needs a manual step.** The package defaults to private
whatever the repo's visibility. Make it public in the package's settings on
GitHub if people should pull it without logging in.

There is no `just` recipe for "cut a release", and a failure partway leaves a
partial release (e.g. the image pushed, then the `.deb` step fails) with no
automatic rollback. Test packaging changes locally before tagging.

## The Docker image builds its own frontend

The root `Dockerfile` has three stages. The build context is the repo root.

1. `frontend-builder`: downloads Flutter's current stable SDK and runs
   `flutter build web --release`.
2. `builder`: installs the backend with `uv`.
3. `runtime`: copies the backend's `.venv/` and the web build (`build/web`) to
   `web/`, where `Settings.web_dir` expects it. See `_mount_web_ui` in
   `backend/src/dinatos_backend/main.py`, and [Container image](backend.md#container-image).

Because the web app is served by the backend, both share one origin and no CORS
setup is needed.

## Android APK signing

`frontend/android/app/build.gradle.kts` reads the signing key from
`frontend/android/key.properties`. Android refuses to install an APK over an
existing one if the signing key differs, and debug keystores are generated per
machine, so debug-signed builds could never update an earlier install.

- **CI:** the workflow writes the keystore from the repository secrets
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
  and optionally `ANDROID_KEY_PASSWORD`. It fails if they are missing.
- **Local builds** without `key.properties` fall back to the debug key.
- **Create the key once**, and never lose or rotate it:

  ```bash
  keytool -genkeypair -v -keystore release.jks -alias dinatos \
      -keyalg RSA -keysize 2048 -validity 10000
  ```

The release manifest (`android/app/src/main/AndroidManifest.xml`) must declare
`android.permission.INTERNET`. Flutter only adds it to debug and profile
manifests. A release APK without it installs fine and then fails every request
as "server not reachable". `just android check-apk` asserts it on a built APK.

## Building locally

Run from the repository root. Needs the Flutter SDK, the Android SDK for the
APK, and the Linux build dependencies below. See
[Environment setup](../development/environment-setup.md).

```bash
just packaging build-apk <version> [build-number]
just packaging build-deb <version>
just packaging build-appimage <version>
just packaging build-linux-artifacts <version>   # both Linux formats, one shared build
```

- The release workflow calls these same recipes.
- APK output: `frontend/build/app/outputs/flutter-apk/`.
- Linux packages go to `dist/`, or to a directory given as the second argument.

### Docker-based Linux builds

`build-deb-docker`, `build-appimage-docker` and `build-linux-artifacts-docker`
take the same arguments but build inside `ubuntu:22.04`
(`packaging/linux/Dockerfile.build`). They need only Docker, and build from a
copy of the checkout so stale `frontend/build/` state is never reused.

Prefer them from a Nix/devbox shell. A binary built there embeds `/nix/store`
library paths and interpreter, so it fails on other machines or cannot find the
host's GL drivers. The non-Docker recipes therefore refuse to run in a devbox
shell. `DINATOS_ALLOW_DEVBOX_BUILD=1` overrides that for a local-only test.

## Linux desktop target

### Build dependencies

`flutter build linux` fails at CMake configure without:

- `libgtk-3-dev`: the windowing toolkit.
- `libsecret-1-dev`: used by `flutter_secure_storage`.
- `clang cmake ninja-build pkg-config`: the rest of the toolchain.

`flutter analyze` and `flutter test` do not need any of this. The
`linux-packages` job installs it with `apt-get`.

### Build on the oldest supported Ubuntu

`linux-packages` runs on `ubuntu-22.04`, deliberately not `ubuntu-latest`. The
bundle links against the build machine's glibc, so a newer build image yields a
package that fails on older systems with `GLIBC_2.38 not found`. Raise the build
image only together with the minimum supported Ubuntu.

### Smoke test

The `linux-smoke` job gates the release. It installs the `.deb` in pristine
`ubuntu:22.04` and `ubuntu:24.04` containers and starts it under Xvfb
(`packaging/linux/smoke-test-deb.sh`; also runnable locally with Docker). It
also runs `ldd` on every bundled library in isolation, with no exemptions:
every library must resolve on a clean machine. This has caught three problems:

- **Plugin rpath.** Plugin libraries (`flutter_secure_storage`, `url_launcher`)
  are installed as plain files, so CMake never rewrites their rpath. Left
  alone it points at the *build tree's* `libflutter_linux_gtk.so`: fine where
  built, `not found` elsewhere. `frontend/linux/CMakeLists.txt` sets `$ORIGIN`
  on them, as for the rest of the bundle.
- **`libdartjni.so`.** The `jni` package's native half (pulled in by
  `path_provider_android`) links `libjvm.so`, which only a JDK has. Nothing on
  desktop uses JNI, so `CMakeLists.txt` leaves the library out of the bundle.
- **GL libraries.** The engine reaches `libgles2` and `libegl1` through
  libepoxy's `dlopen`, which link-time checks cannot see. The `.deb` declares
  them as dependencies (`packaging/linux/build-deb.sh`). Without them the app
  aborts with `Couldn't open libGLESv2.so.2`.

### `flutter create` is not additive

`flutter create --platforms=linux .` on an existing project rewrites
`frontend/.metadata`'s migration list to contain only `linux`, dropping the
`android` and `web` entries. It also touches `analysis_options.yaml`. After
running it for any platform, diff both files and restore what was lost.
