# Releases and packaging

This page explains how Dinatos builds and publishes a release, and how to
build the same artifacts on your computer. A release has the Docker image, the
Linux packages and the Android APK. It is for contributors who change the
packaging, the `Dockerfile` or `release.yml`. For what runs on every pull
request, see [CI and checks](ci.md).

## Cut a release

A release is a Git tag with the name `v<version>`, for example `v1.2.3`. When
you push the tag, `.github/workflows/release.yml` starts. You do not run a
build step by hand. The jobs of the workflow run in parallel.

```bash
just release dry   # print the next patch tag (v1.2.3 -> v1.2.4) without creating it
just release       # create and push that tag at HEAD
```

| Artifact | Built by | Notes |
| --- | --- | --- |
| Docker image (backend plus built web app) | root `Dockerfile` | The workflow scans it with Trivy, then pushes it to `ghcr.io/<owner>/dinatos` with the tags `<version>` and `latest`. Only `linux/amd64`. The comments in the workflow say what `arm64` needs. |
| Linux `.deb` | `packaging/linux/build-deb.sh` | Built from the same `flutter build linux --release` bundle as the AppImage. |
| Linux `.AppImage` (portable) | `packaging/linux/build-appimage.sh` | Built from the same bundle, so the two packages cannot differ. |
| Android APK | `just packaging build-apk` | Signed with the release key. See [Android APK signing](#android-apk-signing). |

The `version` job removes the leading `v` from the tag one time. Because of
this, every artifact and the GitHub Release use one version string. `dpkg-deb`
rejects a leading `v`. The last job, `release`, puts all artifacts into one
GitHub Release.

Before you push a tag, read these cautions:

- **First push to GHCR.** The package is private by default, even if the
  repository is public. To let people pull the image without a login, make the
  package public once, in its settings on GitHub.
- **Scan failure.** If Trivy finds a fixable CRITICAL vulnerability, the
  `docker` job stops before the push. The other jobs continue. See
  [Security scanning](ci.md#security-scanning) for how to fix or accept the
  finding.

> [!WARNING]
> **No rollback.** No `just` recipe undoes a release. If a job fails after
> other jobs finished, the release is partial. For example, the image is on
> GHCR and then the `.deb` step fails. The workflow cannot roll back by itself.
> Before you tag, test changes to `packaging/linux/` or the `Dockerfile` on
> your computer.

## Nightly releases

`nightly.yml` runs every day at 02:17 UTC, or when you start it manually. The
`force` input makes it release even if there are no new commits.

If `main` has no commits since the last nightly release, the workflow does
nothing. Otherwise it calls `release.yml` to publish a GitHub **prerelease**.
The prerelease has the same image, packages and APK. It does not need a `v*`
tag.

| Item | Value |
|---|---|
| Tag | `nightly-YYYYMMDD`. A second release on the same day gets `.2`, then `.3`, and so on. |
| Version | The newest `v*` tag (or the `pyproject.toml` version if there is none) with the minor number increased by 1, then `-nightly.YYYYMMDD`. Example: `1.3.3-nightly.20261014` |
| Python package version | `<base>.devYYYYMMDD[N]`. The nightly version is not valid PEP 440. |
| Docker tags | The version and a moving `nightly` tag. Only stable releases move `latest`. |
| Retention | The 14 newest nightly releases and their tags. The workflow does not remove old images from GHCR. |

A `v*` tag does not fit a nightly release for two reasons. It starts
`release.yml` as a stable release. It also sorts among the real versions.
A tag that a workflow pushes with `GITHUB_TOKEN` cannot start another
workflow. For this reason, the nightly workflow calls `release.yml` directly
(`workflow_call`).

The Docker build writes the version into `pyproject.toml` of the backend. The
API, its OpenAPI document and the backups report this version.

## Build the artifacts locally

Run the commands from the root of the repository. You need the Flutter SDK,
the Android SDK (for the APK) and the Linux build dependencies in
[Linux desktop target](#linux-desktop-target). For the tools, see
[Environment setup](environment-setup.md).

```bash
just packaging build-apk <version> [build-number]
just packaging build-deb <version>
just packaging build-appimage <version>
just packaging build-linux-artifacts <version>   # both Linux formats, one shared build
just docker build                                # the Docker image
```

- The release workflow calls these same recipes.
- The APK is in `frontend/build/app/outputs/flutter-apk/`.
- The Linux packages go to `dist/`. You can give a different directory as the
  second argument.

### Docker-based Linux builds

The recipes `build-deb-docker`, `build-appimage-docker` and
`build-linux-artifacts-docker` take the same arguments. They build inside
`ubuntu:22.04` (`packaging/linux/Dockerfile.build`). They need only Docker.
They build from a copy of the checkout, so they never reuse old
`frontend/build/` state.

Use these recipes in a Nix or devbox shell. A binary that you build in such a
shell contains the `/nix/store` paths of the libraries and the interpreter. On
other machines, it fails, or it cannot find the GL drivers of the host. For
this reason, the recipes that do not use Docker refuse to run in a devbox
shell. To override this for a test on your machine only, set
`DINATOS_ALLOW_DEVBOX_BUILD=1`.

## The Docker image builds its own frontend

The root `Dockerfile` has three stages. The build context is the root of the
repository.

1. `frontend-builder`: downloads the current stable Flutter SDK and runs
   `flutter build web --release`.
2. `builder`: installs the backend with `uv`.
3. `runtime`: copies the `.venv/` of the backend and the web build
   (`build/web`) to `web/`. `Settings.web_dir` expects the web build there.
   See `_mount_web_ui` in `backend/src/dinatos_backend/main.py` and
   [Container image](../architecture/backend.md#container-image).

The backend serves the web app. Both use one origin, so the image does not
need a CORS setup.

## Android APK signing

`frontend/android/app/build.gradle.kts` reads the signing key from
`frontend/android/key.properties`. Android does not install an APK over an
existing APK if the signing key is different. Each machine generates its own
debug keystore. For this reason, a debug-signed build can never update an
earlier install.

- **In CI:** the workflow writes the keystore from the repository secrets
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
  and, as an option, `ANDROID_KEY_PASSWORD`. The workflow fails if the
  required secrets are missing.
- **In local builds:** if `key.properties` does not exist, the build uses the
  debug key.
- **To create the key:** do this one time. Never lose the key and never rotate
  it.

  ```bash
  keytool -genkeypair -v -keystore release.jks -alias dinatos \
      -keyalg RSA -keysize 2048 -validity 10000
  ```

The release manifest (`android/app/src/main/AndroidManifest.xml`) must declare
`android.permission.INTERNET`. Flutter adds this permission only to the debug
and profile manifests. A release APK without it installs correctly. Then every
request fails with "server not reachable". The command
`just android check-apk` checks the permission on a built APK.

## Linux desktop target

### Build dependencies

`flutter build linux` fails at the CMake configure step if these packages are
missing:

- `libgtk-3-dev`: the windowing toolkit.
- `libsecret-1-dev`: used by `flutter_secure_storage`.
- `clang cmake ninja-build pkg-config`: the rest of the toolchain.

`flutter analyze` and `flutter test` do not need these packages. The
`linux-packages` job installs them with `apt-get`.

### Build on the oldest supported Ubuntu

The `linux-packages` job runs on `ubuntu-22.04`. It does not use
`ubuntu-latest`, on purpose. The bundle links against the glibc of the build
machine. A newer build image makes a package that fails on older systems with
`GLIBC_2.38 not found`. Raise the build image only together with the minimum
supported Ubuntu.

### Smoke test

The `linux-smoke` job must pass before the release. It installs the `.deb` in
clean `ubuntu:22.04` and `ubuntu:24.04` containers. It starts the app under
Xvfb (`packaging/linux/smoke-test-deb.sh`). You can also run this script
locally with Docker. The job also runs `ldd` on each bundled library alone,
with no exemptions. Every library must resolve on a clean machine. The job
found three problems:

- **Plugin rpath.** The packaging installs the plugin libraries
  (`flutter_secure_storage`, `url_launcher`) as plain files. CMake does not
  rewrite their rpath. Without a change, the rpath points to the
  `libflutter_linux_gtk.so` in the *build tree*. This works on the machine
  that built the app, and shows `not found` on other machines.
  `frontend/linux/CMakeLists.txt` sets `$ORIGIN` on these libraries, as it
  does for the rest of the bundle.
- **`libdartjni.so`.** This is the native part of the `jni` package, which
  `path_provider_android` pulls in. It links `libjvm.so`, and only a JDK has
  that library. Nothing on desktop uses JNI, so `CMakeLists.txt` leaves the
  library out of the bundle.
- **GL libraries.** The engine reaches `libgles2` and `libegl1` through the
  `dlopen` of libepoxy. Link-time checks cannot see this. The `.deb` declares
  both as dependencies (`packaging/linux/build-deb.sh`). Without them, the app
  stops with `Couldn't open libGLESv2.so.2`.

### `flutter create` is not additive

The command `flutter create --platforms=linux .` changes an existing project.
It rewrites the migration list in `frontend/.metadata` so that it has only
`linux`. It removes the `android` and `web` entries. It also changes
`analysis_options.yaml`. After you run it for any platform, compare both files
with the old versions. Restore what the command removed.
