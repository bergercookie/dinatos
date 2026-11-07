# CI and releases

This page explains what GitHub Actions runs on your pull request. It also
explains how releases, nightly builds, the docs site and link checks work. The
workflows are in `.github/workflows/`.

## CI on every PR

`ci.yml` runs on every pull request and on every push to `main`. Each job
matches a recipe that you can run before you push:

| CI job | Local equivalent | Needs |
|---|---|---|
| `check` | `just check` | Python, `uv` |
| `migrations` | `just backend test-migrations` | Docker |
| `frontend` | `just frontend check` | Flutter SDK |
| `e2e` | `just e2e test` | Docker, Flutter SDK, Chromium |
| `coverage` | None. It merges the numbers from `check` and `frontend`. | |

Notes:

- The `check` job also fails if `uv.lock` is out of date. After you change a
  dependency in a `pyproject.toml`, run `uv lock`.
- If a browser test fails, the `e2e` job uploads a screenshot (artifact
  `e2e-debug`).
- For the tool requirements, see [Environment setup](environment-setup.md).
  For what each recipe does, see [Running and testing](workflow.md).

### Coverage

Pytest-cov measures the backend and `mcp_server`. Both must keep 100% line
coverage and 100% branch coverage. The Flutter frontend (`just frontend
coverage`) must keep at least 50% line coverage. The `e2e` job is not
measured. No external service takes part.

- **PR comment.** The `coverage` job (`.github/scripts/coverage_report.py`)
  adds a comment to your PR. The comment shows the coverage of the backend, the
  MCP server and the frontend. It compares them with the latest run on `main`.
  The job updates the same comment on each push. On a PR from a fork, the token has read-only access, so the comment can be missing. The numbers are still on
  the summary page of each job.
- **Reports.** The summary page of the run shows a table for each file. The
  `check` job and the `frontend` job upload HTML reports that you can browse
  (`backend-coverage-html`, `frontend-coverage-html`).
- **Local reports.** To write the same reports on your computer, run
  `just backend coverage`, `just mcp_server coverage` and
  `just frontend coverage`.

### PR and issue templates

`.github/pull_request_template.md` asks for what and why, a passing
`just check`, and tests. `.github/ISSUE_TEMPLATE/` has a bug-report form and a
feature-request form. Blank issues are off. The configuration sends security
reports to a private advisory form.

## Documentation site

`docs.yml` runs on a push to `main`, or when you start it manually. It runs
`just install` and `just docs docs`. Then it publishes `docs/_build/html` to
GitHub Pages.

```bash
just docs docs         # build; warnings are errors (-W --keep-going)
just docs docs-serve   # serve on http://127.0.0.1:8000; rebuild and reload on every edit
```

`docs-serve` also watches `README.md`, `CONTRIBUTING.md` and `screenshots/`.
These files are outside `docs/`, but the index pages include them. It does not
fail on warnings, so run `just docs docs` before you push.

A broken cross-link or toctree entry fails the build locally and in CI. `just
check` includes the build.

## Link checking

[lychee](https://github.com/lycheeverse/lychee) checks the links in
`README.md`, `CONTRIBUTING.md`, `AGENTS.md` and `docs/**`. The file
`lychee.toml` has the configuration. It also gives the reason for each
exclusion.

- **Offline check, part of `just check`.** The `lychee-offline` pre-commit
  hook checks relative links and `#anchors`. It does not use the network, so
  it does not fail at random.
- **Online check, not part of `just check`.** `just check-links` also fetches
  external URLs. `links.yml` runs it every week, on request, and on PRs that
  change Markdown files. The blocking `check` job does not include it. An
  outage of a third-party site must not block unrelated PRs. To exclude a host
  that is valid but unreliable, add it to `lychee.toml` with a comment.

`.pre-commit-config.yaml` and the root `justfile` both set the version of `lychee-bin`. When you change the version, change both files.

## Security scanning

[Trivy](https://trivy.dev) looks for known vulnerabilities, committed secrets
and unsafe configuration. New CVEs appear without any commit, so the scans run
in three places. The file `trivy.yaml` holds the settings that all of them
share. Only fixable HIGH and CRITICAL findings count, because no PR can act on
a CVE that has no fix.

| Scan | When | What it checks | Effect of a finding |
|---|---|---|---|
| Dependencies and secrets | Every PR, and weekly | `uv.lock`, `pubspec.lock`, the working tree | The job fails |
| Configuration | Every PR, and weekly | The `Dockerfile` and other infrastructure files | The job fails |
| Image, before the push | Every release and nightly | The built Docker image | A fixable CRITICAL finding stops the release |
| Published image | Weekly | `ghcr.io/<owner>/dinatos:latest` | A CRITICAL finding fails the job |

The `trivy.yml` workflow runs the first two scans and the weekly image scan.
The `docker` job in `release.yml` builds the image, scans it, and pushes it
only if the scan passes. The scan is before the push on purpose, because you
cannot take a pushed image back.

To run the dependency, secret and configuration scans on your computer, run
`just trivy`. This needs Docker and network access. It is not part of
`just check`, because it downloads the Trivy database.

If a finding blocks you and the fix is not possible, add the finding to
`.trivyignore.yaml`. Give each entry a reason (`statement`) and an expiry date
(`expired_at`). The finding then returns for review.

Notes:

- Trivy reads `pubspec.lock`, but its advisory data for Dart is thinner than
  for Python. Treat the Flutter result as a best effort.
- The configuration scan covers the `Dockerfile` best. It overlaps with
  `hadolint` and `actionlint`, which stay as they are.
- The workflows print the results in the job log. They do not upload them to
  the GitHub code-scanning tab.

## Lint hooks

`just check` runs `just lint`. This recipe runs every pre-commit hook over the
whole tree. Besides ruff, mypy, tach and the lychee offline check, these hooks
run:

- `hadolint` lints the `Dockerfile`.
- `shellcheck` (`--severity=style`) and `shfmt` (2-space indent, check only)
  lint the shell scripts in `backend/`, `packaging/linux/` and `tools/`. A file
  with a shebang must be executable. To fix the format, run
  `uvx --from shfmt-py shfmt -i 2 -w <file>`.
- `markdownlint-cli2` lints the Markdown files. The rules are in
  `.markdownlint-cli2.yaml`.
- `vale` checks the prose of the README, `CONTRIBUTING.md` and `docs/`. It
  finds passive voice, vague words, filler sentence openers and misspellings. The rules are in `.vale.ini`.
  If Vale does not know a product or technical term, add the term to
  `.vale/styles/config/vocabularies/Dinatos/accept.txt`. To run only this
  check, run `uvx pre-commit run vale --all-files`.
- `actionlint` lints the GitHub Actions workflows. It checks expressions,
  `needs:` references and action inputs.
- `check-xml` checks that the Android manifests and resources are well-formed
  XML.
- `desktop-file-validate` validates `packaging/linux/dinatos.desktop`.

Pre-commit installs all hooks as wheels or through `uvx`, with one exception.
`desktop-file-validate` needs the system package `desktop-file-utils`. To
install it, run `apt install desktop-file-utils`. CI installs it. To install
the hooks as git pre-commit hooks, run `just hooks`.

## Releases

A release is a Git tag with the name `v<version>`, for example `v1.2.3`. When
you push the tag, `release.yml` starts. You do not run a build step by hand.

```bash
just release dry   # print the next patch tag (v1.2.3 -> v1.2.4) without creating it
just release       # create and push that tag at HEAD
```

The workflow builds these items in parallel:

- **Docker image** (the backend and the built web app). The workflow scans it
  with Trivy, then pushes it to `ghcr.io/<owner>/dinatos` with the tags
  `<version>` and `latest`. It is for `linux/amd64` only. The `Dockerfile`
  builds the Flutter web app in an earlier stage.
- **Linux desktop client** as a `.deb` package and an `.AppImage` file. Both
  come from one `flutter build linux --release` bundle.
- **Android APK**, signed with the debug key. A real release keystore does not
  exist yet.

A `version` job removes the leading `v` once. For this reason, every artifact
and the GitHub Release have the same version. A last `release` job puts all
artifacts into one GitHub Release.

Before you push a tag, read these cautions:

- **First push to GHCR.** The package is private by default, even if the
  repository is public. Make the package public once, in its GitHub settings.
- **No rollback.** Warning: if a later step fails, the partial release stays
  on GHCR. For example, the `.deb` step can fail after the workflow pushed the
  Docker image. Before you tag, test changes to `packaging/linux/` or the
  `Dockerfile` on your computer.
- **Scan failure.** If Trivy finds a fixable CRITICAL vulnerability, the
  `docker` job stops before the push. The other jobs continue. See
  [Security scanning](#security-scanning) for how to fix or accept the finding.

### Building the artifacts locally

The workflow calls the same recipes:

```bash
just packaging build-apk <version> [build-number]
just packaging build-deb <version>
just packaging build-appimage <version>
just packaging build-linux-artifacts <version>   # .deb and AppImage, one shared build
just docker build                                # the Docker image
```

The APK goes to `frontend/build/app/outputs/flutter-apk/`. The Linux packages
go to `dist/`, or to the directory that you give as the second argument. The
Linux build needs the `apt` packages listed in
[Environment setup](environment-setup.md#flutter-sdk).

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
