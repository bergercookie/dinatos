# Distribution

Pushing a `v*` tag (e.g. `v1.2.3`) runs `.github/workflows/release.yml`,
which builds and publishes, in parallel, everything a release needs:

- The backend and the built web app together, as one Docker image pushed to
  `ghcr.io/<owner>/dinatos`, tagged with the version and `latest`
  (`linux/amd64` only -- see the workflow's own comment on what adding
  `linux/arm64` would need). See "The Docker image builds its own frontend"
  below.
- The Linux desktop client, packaged both as a `.deb`
  (`packaging/linux/build-deb.sh`) and a portable `.AppImage`
  (`packaging/linux/build-appimage.sh`) -- both from the same
  `flutter build linux --release` bundle, so the two scripts can't drift
  apart on what they're packaging.
- An Android APK, signed with a stable release key read from
  `frontend/android/key.properties` (`android/app/build.gradle.kts`). Android
  refuses to install an APK over an existing install if the signing key
  differs, and the debug keystore is generated fresh on every machine -- so
  debug-signed CI builds could never update an earlier install. The workflow
  writes the keystore from the `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and (optional)
  `ANDROID_KEY_PASSWORD` repository secrets and fails if they are missing.
  Local builds without `key.properties` fall back to the debug key. Create a
  key once with `keytool -genkeypair -v -keystore release.jks -alias dinatos
  -keyalg RSA -keysize 2048 -validity 10000`, and never lose or rotate it.

The same artifacts can be produced locally from the repository root:

```bash
just packaging build-apk <version> [build-number]
just packaging build-deb <version>
just packaging build-appimage <version>
just packaging build-linux-artifacts <version>   # both Linux formats, one shared build
```

`just packaging build-deb-docker <version>` (likewise `build-appimage-docker`
and `build-linux-artifacts-docker`) builds inside an
`ubuntu:22.04` container (`packaging/linux/Dockerfile.build`) and needs only
Docker on the host. Prefer it for local builds from a Nix/devbox shell: a
binary built there embeds `/nix/store` library paths and interpreter, so the
resulting package doesn't run on other machines (or fails to find the host's
GL drivers) -- which is why the non-Docker `build-deb`/`build-appimage`/
`build-linux-artifacts` recipes refuse to run inside a devbox shell
(`DINATOS_ALLOW_DEVBOX_BUILD=1` overrides, for a local-only test). It builds from a copy of the checkout, so stale host
`frontend/build/` state is never reused.

Otherwise, Linux build dependencies and the Flutter/Android toolchains must already be
installed -- see [Environment setup](../development/environment-setup.md).
The release workflow calls these same recipes, keeping local and published
builds on the same path. APK output is under
`frontend/build/app/outputs/flutter-apk/`; Linux packages default to
`dist/`, or accept a different output directory as their second argument.

A `version` job computes the release version once (the tag with its leading
`v` stripped) so every artifact and the GitHub Release itself agree on the
same string, then a final `release` job gathers everything into one GitHub
Release. **First push to GHCR from a repo needs a one-time manual step**:
the pushed package defaults to private regardless of the repo's own
visibility, so make it public from the package's own settings page on
GitHub if it should be downloadable without authentication.

## The Linux desktop target needs its own apt packages

`flutter build linux` fails at the CMake configure step without
`libgtk-3-dev` (the renderer's windowing toolkit) and `libsecret-1-dev`
(what `flutter_secure_storage` links against on Linux) already installed --
`clang cmake ninja-build pkg-config` cover the rest of the toolchain itself.
None of this is needed for `flutter analyze`/`flutter test`, only for
actually building this one platform target;
`.github/workflows/release.yml`'s `linux-packages` job installs all of it
via `apt-get` before building.

That job runs on `ubuntu-22.04`, deliberately not `ubuntu-latest`: the
bundle links against the build machine's glibc, so building on a newer
Ubuntu yields a package that fails on older ones with
`GLIBC_2.38 not found`. The `linux-smoke` job then installs the `.deb` in
pristine `ubuntu:22.04` and `ubuntu:24.04` containers and starts it under
Xvfb (`packaging/linux/smoke-test-deb.sh`, also runnable locally with
Docker) and gates the release on it. Raise the build image only together
with the minimum supported Ubuntu.

The smoke test runs `ldd` on every library in the bundle, in isolation, which
turned up two things worth knowing:

- The plugin libraries (`flutter_secure_storage`, `url_launcher`) are installed
  as plain files, so CMake never rewrites their rpath, and left alone it is the
  *build tree's* path to `libflutter_linux_gtk.so` -- fine on the machine that
  built them, `not found` anywhere else. `frontend/linux/CMakeLists.txt` gives
  them `$ORIGIN`, like the rest of the bundle.
- `libdartjni.so` (the `jni` package's native half, pulled in transitively by
  `path_provider_android`) links `libjvm.so`, which only a JDK has. Nothing on
  desktop uses JNI -- Android's `path_provider` implementation never runs here
  -- so the library is just an unloadable file, and `CMakeLists.txt` leaves it
  out of the bundle. Every library in the bundle must resolve on a clean
  machine; the smoke test has no exemptions.

Starting the app in the container is what found a third: the engine reaches
`libgles2`/`libegl1` through libepoxy's `dlopen`, which no link-time check
sees, so the `.deb` declares them as dependencies -- without them the app
aborts with `Couldn't open libGLESv2.so.2`.

`flutter create --platforms=linux .` on an existing project is not purely
additive: it rewrote `.metadata`'s migration list to contain only `linux`,
silently dropping the existing `android`/`web` entries, which had to be
restored by hand. Diff `.metadata` (and `analysis_options.yaml`, which it
also touches) after running this for any other platform, rather than
assuming it only adds what you asked for.

## Releases are cut from a tag, not from `main` branch state directly

There's no `just` recipe for "cut a release" -- see
[CI and releases](../development/ci-and-releases.md) for the full workflow
breakdown and why testing packaging changes locally before tagging matters:
a failure partway through the release workflow (e.g. the `.deb` step
failing after the Docker image already pushed) leaves a real,
partially-published state on GHCR with no automatic rollback.
