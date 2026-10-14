# CI and releases

What GitHub Actions runs on your pull request, and how releases, nightly
builds, the docs site and link checks work. Workflows live in
`.github/workflows/`.

## CI on every PR

`ci.yml` runs on every pull request and every push to `main`. Each job maps
to a recipe you can run before pushing:

| CI job | Local equivalent | Needs |
|---|---|---|
| `check` | `just check` | Python, `uv` |
| `migrations` | `just backend test-migrations` | Docker |
| `frontend` | `just frontend check` | Flutter SDK |
| `e2e` | `just e2e test` | Docker, Flutter SDK, Chromium |
| `coverage` | none (merges the numbers from `check` and `frontend`) | |

Notes:

- `check` also fails if `uv.lock` is stale. After editing a `pyproject.toml`
  dependency, run `uv lock`.
- `e2e` uploads a screenshot when a browser test fails (artifact `e2e-debug`).
- See [Environment setup](environment-setup.md) for tool requirements and
  [Running and testing](workflow.md) for what each recipe does.

### Coverage

Backend and `mcp_server` are measured with pytest-cov and must stay at 100%
line and branch coverage. The Flutter frontend (`just frontend coverage`) must
stay at or above 50% line coverage. `e2e` is not measured. No external service
is involved.

- **PR comment.** The `coverage` job
  (`.github/scripts/coverage_report.py`) comments backend, MCP server and
  frontend coverage on your PR, compared with the latest run on `main`. It
  updates the same comment on each push. On PRs from forks the token is
  read-only, so the comment may be missing; the numbers are still on each
  job's summary page.
- **Reports.** Per-file tables appear on the run's summary page. The `check`
  and `frontend` jobs upload browsable HTML (`backend-coverage-html`,
  `frontend-coverage-html`).
- **Locally.** `just backend coverage`, `just mcp_server coverage` and
  `just frontend coverage` write the same reports.

### PR and issue templates

`.github/pull_request_template.md` asks for what and why, a passing
`just check`, and tests. `.github/ISSUE_TEMPLATE/` has bug-report and
feature-request forms. Blank issues are off, and the config sends security
reports to a private advisory form.

## Documentation site

`docs.yml` runs on push to `main` (or manually). It runs `just install` and
`just docs docs`, then publishes `docs/_build/html` to GitHub Pages.

```bash
just docs docs         # build; warnings are errors (-W --keep-going)
just docs docs-serve   # build, then serve on http://127.0.0.1:8000
```

A broken cross-link or toctree entry fails the same way locally and in CI.
`just check` includes the build.

## Link checking

[lychee](https://github.com/lycheeverse/lychee) checks links in `README.md`,
`CONTRIBUTING.md`, `AGENTS.md` and `docs/**`. Its config, including each
exclusion and why, is `lychee.toml`.

- **Offline, in `just check`**: the `lychee-offline` pre-commit hook checks
  relative links and `#anchors`. No network, so it cannot flake.
- **Online, not in `just check`**: `just check-links` also fetches external
  URLs. `links.yml` runs it weekly, on demand, and on PRs that touch Markdown.
  It is not part of the blocking `check` job, because a third-party outage
  must not block unrelated PRs. Exclude a flaky-but-valid host in
  `lychee.toml` with a comment.

The `lychee-bin` version is pinned in both `.pre-commit-config.yaml` and the
root `justfile`. Bump both together.

## Other lint hooks (run by `just check`)

- `hadolint` lints the `Dockerfile`.
- `shellcheck` (`--severity=style`) and `shfmt` (2-space indent, check only)
  lint shell scripts in `backend/`, `packaging/linux/` and `tools/`. Files with
  a shebang must be executable. Fix formatting with
  `uvx --from shfmt-py shfmt -i 2 -w <file>`.
- `markdownlint-cli2` lints Markdown; rules are in `.markdownlint-cli2.yaml`.

All are pre-commit hooks installed as wheels or via `uvx`, so nothing needs
installing system-wide. `just hooks` installs them as git pre-commit hooks.

## Releases

A release is a Git tag named `v<version>` (for example `v1.2.3`). Pushing the
tag triggers `release.yml`. There is no manual build step.

```bash
just release dry   # print the next patch tag (v1.2.3 -> v1.2.4) without creating it
just release       # create and push that tag at HEAD
```

The workflow builds these in parallel:

- **Docker image** (backend plus built web app), pushed to
  `ghcr.io/<owner>/dinatos` as `<version>` and `latest` (`linux/amd64` only).
  The `Dockerfile` builds the Flutter web app itself in an earlier stage.
- **Linux desktop client** as a `.deb` and an `.AppImage`, from one
  `flutter build linux --release` bundle.
- **Android APK**, debug-signed. A real release keystore is not set up yet.

A `version` job strips the leading `v` once so every artifact and the GitHub
Release agree on the version. A final `release` job gathers everything into one
GitHub Release.

Caveats:

- **First push to GHCR.** The package defaults to private even if the repo is
  public. Make it public once in the package's GitHub settings.
- **No rollback.** If a later step fails (for example the `.deb` after the
  Docker image was pushed), the partial release stays on GHCR. Test changes to
  `packaging/linux/` or the `Dockerfile` locally before tagging.

### Building the artifacts locally

The workflow calls these same recipes:

```bash
just packaging build-apk <version> [build-number]
just packaging build-deb <version>
just packaging build-appimage <version>
just packaging build-linux-artifacts <version>   # .deb and AppImage, one shared build
just docker build                                # the Docker image
```

The APK lands in `frontend/build/app/outputs/flutter-apk/`. Linux packages
go to `dist/`, or to the directory you pass as the second argument. The
Linux build needs the apt packages listed in
[Environment setup](environment-setup.md#flutter-sdk).

## Nightly releases

`nightly.yml` runs daily at 02:17 UTC, or manually (the `force` input
releases even with no new commits). If `main` has no commits since the last
nightly, it does nothing. Otherwise it calls `release.yml` to publish a GitHub
**prerelease** with the same image, packages and APK. No `v*` tag is needed.

| Item | Value |
|---|---|
| Tag | `nightly-YYYYMMDD`; a second one the same day is `.2`, `.3`, and so on |
| Version | newest `v*` tag (else the `pyproject.toml` version) with the minor bumped, then `-nightly.YYYYMMDD`. Example: `1.3.3-nightly.20261014` |
| Python package version | `<base>.devYYYYMMDD[N]`, because the nightly version is not valid PEP 440 |
| Docker tags | the version and a moving `nightly`; `latest` follows stable releases only |
| Retention | the 14 newest nightlies and their tags. Old images on GHCR are not pruned |

Why not a `v*` tag: it would trigger `release.yml` as a stable release and sort
among real versions. A tag pushed with `GITHUB_TOKEN` cannot start a workflow
anyway, so the nightly calls `release.yml` directly (`workflow_call`).

The Docker build stamps the version into the backend's `pyproject.toml`, so
the API, its OpenAPI document and backups report it.
