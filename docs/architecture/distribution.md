# Distribution

Pushing a `v*` tag (e.g. `v1.2.3`) runs `.github/workflows/release.yml`,
which builds and publishes, in parallel, everything a release needs:

- The backend, as a Docker image pushed to
  `ghcr.io/<owner>/dinatos-backend`, tagged with the version and `latest`
  (`linux/amd64` only -- see the workflow's own comment on what adding
  `linux/arm64` would need).
- The Linux desktop client, packaged both as a `.deb`
  (`packaging/linux/build-deb.sh`) and a portable `.AppImage`
  (`packaging/linux/build-appimage.sh`) -- both from the same
  `flutter build linux --release` bundle, so the two scripts can't drift
  apart on what they're packaging.
- An Android APK, debug-signed: `android/app/build.gradle.kts`'s release
  build type still points at the debug signing config, deliberately, since a
  real release keystore is future work, not a gap in the workflow itself.

The same artifacts can be produced locally from the repository root:

```bash
just packaging build-apk <version> [build-number]
just packaging build-deb <version>
just packaging build-appimage <version>
just packaging build-linux-artifacts <version>   # both Linux formats, one shared build
```

Linux build dependencies and the Flutter/Android toolchains must already be
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
