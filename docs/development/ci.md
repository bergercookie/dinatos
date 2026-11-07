# CI and checks

This page explains what GitHub Actions runs on your pull request: the tests,
the linters, the docs build, link checks and security scans. The workflows are
in `.github/workflows/`. For releases and nightly builds, see
[Releases and packaging](releases.md).

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
- `no-github-file-links` rejects a Markdown link to a file view of this
  repository on GitHub (a `blob` or `tree` URL). Link to the matching page of
  the docs site instead. Links to issues, releases and advisories are fine.
- `vale` checks the prose of the README, `CONTRIBUTING.md` and `docs/`. It
  finds passive voice, vague words, filler sentence openers and misspellings. The rules are in `.vale.ini`.
  If Vale does not know a product or technical term, add the term to
  `.vale/styles/config/vocabularies/Dinatos/accept.txt`. To run only this
  check, run `uvx pre-commit run vale --all-files`.
- `actionlint` lints the GitHub Actions workflows. It checks expressions,
  `needs:` references and action inputs.
- `check-xml` checks that the Android manifests and resources are well-formed
  XML.

Pre-commit installs every hook by itself, as wheels, through `uvx`, or with
its own copy of Node. You do not need system packages from your
distribution. To install the hooks as git pre-commit
hooks, run `just hooks`.
