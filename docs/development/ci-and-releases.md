# CI and releases

## What CI runs

`.github/workflows/ci.yml` triggers on every push to `main` and every PR,
with five independent jobs -- each maps to a `just` recipe you can run
locally before pushing:

| CI job | Local equivalent | Needs |
|---|---|---|
| `check` | `just check` | Nothing beyond Python/`uv` |
| `migrations` | `just backend test-migrations` | Docker |
| `frontend` | `just frontend check` | Flutter SDK |
| `e2e` | `just e2e test` | Docker, Flutter SDK, Playwright's Chromium |

`check` also verifies the `uv` lockfile is up to date before running
`just install`/`just check` -- a dependency added to `pyproject.toml` without
running `uv lock` fails here, not silently. `e2e` uploads a
screenshot of the page at the moment a browser test failed.

## Coverage

Backend and `mcp_server` (pytest-cov, `--cov` in each `pyproject.toml`'s
`addopts`, 100% line+branch gate) and the Flutter frontend
(`just frontend coverage`: `flutter test --coverage` -> `coverage/lcov.info`,
50% line gate) are all measured on every CI run; `e2e` is not. Nothing is
sent to an external service: each run's summary page shows the backend and
`mcp_server` per-file tables and the frontend total, and the `check` and
`frontend` jobs upload browsable HTML (`backend-coverage-html`,
`frontend-coverage-html`; `mcp_server` has none in CI). Locally, `just
backend coverage`, `just mcp_server coverage` and `just frontend coverage`
write the same reports.

See [Environment setup](environment-setup.md) for what each of these needs
installed, and [Running and testing](workflow.md) for what each recipe
actually does.

## Documentation site

`.github/workflows/docs.yml` triggers on push to `main` (and manually, via
`workflow_dispatch`): a `build` job runs `just install` then
`just docs docs`, uploads `docs/_build/html`, and a `deploy` job publishes it
to GitHub Pages. Building it locally (`just docs docs`, or `just docs
docs-serve` to also serve it on `http://127.0.0.1:8000` while you edit) uses
the exact same `-W --keep-going` Sphinx invocation, so a broken cross-link
or toctree entry fails the same way locally as it would in CI.

## Link checking

[lychee](https://github.com/lycheeverse/lychee) checks every link in the
repo's Markdown (`README.md`, `CONTRIBUTING.md`, `AGENTS.md`, `docs/**`),
configured in `lychee.toml` (exclusions for placeholder/localhost URLs and
build output live there, each with its reason). It runs in two places:

- **Offline, in `just check`**: the `lychee-offline` pre-commit hook checks
  relative links and `#anchors` between files, with no network, in well under
  a second -- so it can't flake and is safe to block on.
- **Online, outside `just check`**: `just check-links` also fetches every
  external URL. `.github/workflows/links.yml` runs it weekly, on demand and on
  PRs touching Markdown, but it is not part of the blocking `check` job: a
  third-party site going down must not block unrelated PRs. A flaky-but-valid
  host gets excluded in `lychee.toml` with a comment, not retried forever.

Both use the `lychee-bin` PyPI wheel, pinned in `.pre-commit-config.yaml` and
the root `justfile` (bump both together).

## Nightly releases

`.github/workflows/nightly.yml` runs daily (02:17 UTC, or manually via
`workflow_dispatch`, which can `force` a release). If `main` has no commits
since the previous nightly it does nothing (unless run manually with
`force`); otherwise -- with no new `v*` tag required -- it calls
`release.yml` (via `workflow_call`) to publish a GitHub **prerelease** with
the same Docker image, `.deb`/AppImage and APK.

- **Tag**: `nightly-YYYYMMDD` (a second release the same day gets
  `nightly-YYYYMMDD.2`, `.3`, ... rather than being skipped), not `v<version>.nightly`. A `v*` tag would
  trigger `release.yml` as a stable release, would sort next to real
  versions, and a tag pushed with `GITHUB_TOKEN` can't start a workflow
  anyway -- hence `workflow_call`.
- **Version string** in the packages: `<newest v* tag, else pyproject
  version>-nightly.YYYYMMDD` (plus the same `.N` suffix when the tag has one).
  A nightly is built from `main` and named after the newest tag whether or not
  a tag was pushed since the previous nightly.
- **Docker**: tagged with that version and the moving `nightly` tag;
  `latest` only ever follows stable releases.
- Only the 14 newest nightly releases (and their tags) are kept. Old
  nightly images on GHCR are not pruned.

## Cutting a release

There's no `just` recipe for "cut a release" -- pushing a `v*` tag (e.g.
`v1.2.3`) is what triggers `.github/workflows/release.yml`, which builds and
publishes everything a release needs, in parallel:

- The backend and the built web app together, as one Docker image pushed to
  `ghcr.io/<owner>/dinatos`, tagged with the version and `latest`
  (`linux/amd64` only). This job's own `Dockerfile` build (context: the repo
  root) fetches and builds the Flutter web app itself as one of its stages,
  so it needs no `subosito/flutter-action` step, unlike the two Flutter jobs
  below.
- The Linux desktop client, packaged both as a `.deb` and a portable
  `.AppImage`, both from the same `flutter build linux --release` bundle.
- An Android APK, debug-signed (a real release keystore is future work, not
  a gap in the workflow itself).

A `version` job computes the release version once (the tag with its leading
`v` stripped) so every artifact and the GitHub Release itself agree on the
same string; a final `release` job gathers everything into one GitHub
Release.

**First push to GHCR from a repo needs a one-time manual step**: the pushed
package defaults to private regardless of the repo's own visibility, so make
it public from the package's own settings page on GitHub if it should be
downloadable without authentication.

### Building the same artifacts locally

The release workflow calls the same recipes below, so local and published
builds stay on the same path:

```bash
just packaging build-apk <version> [build-number]
just packaging build-deb <version>
just packaging build-appimage <version>
just packaging build-linux-artifacts <version>   # both Linux formats, one shared Flutter build
```

APK output lands under `frontend/build/app/outputs/flutter-apk/`; Linux
packages default to `dist/`, or accept a different output directory as
their second argument. Test any change to `packaging/linux/`'s scripts or
the root `Dockerfile` locally (`just docker build`, or a plain
`docker build .` from the repo root) before tagging -- a failure partway
through the release workflow (e.g. the `.deb` step failing after the Docker
image already pushed) leaves a real, partially-published state on GHCR with
no automatic rollback.

`hadolint` lints the `Dockerfile` as a pre-commit hook, so most Dockerfile
mistakes are caught by `just check` well before a release build.

Shell scripts (`backend/docker-entrypoint.sh`, `packaging/linux/*.sh`,
`tools/*.sh`) are covered the same way: `shellcheck` (at `--severity=style`)
and `shfmt` (2-space indent, check-only) run as pre-commit hooks, along with
checks that anything with a shebang is executable. Both ship as wheels, so
nothing needs installing system-wide. Fix formatting with
`uvx --from shfmt-py shfmt -i 2 -w <file>`.

Markdown (README, `AGENTS.md`, `docs/`) is linted the same way by
`markdownlint-cli2`; its rules live in `.markdownlint-cli2.yaml`.
