# Dinatos frontend

The Flutter client for [Dinatos](../README.md), a self-hosted workout tracker.
One codebase targets web, Android and Linux desktop. It talks to the backend's
REST API. This page is for contributors working on the app.

## Quick start

Needs the Flutter SDK and [`just`](https://github.com/casey/just); see
[Environment setup](../docs/development/environment-setup.md). Run from
`frontend/`, or from the repo root as `just frontend <recipe>`.

```bash
just install   # flutter pub get
just check     # format check, flutter analyze, flutter test (headless; no browser or device)
just run       # web dev server on port 8081 with hot reload; needs a running backend
```

`just --list` shows the rest (`test`, `coverage`, `fmt`, `build-web`).

## Where to read next

- [Frontend architecture](../docs/architecture/frontend.md): code layout and
  design decisions.
- [Running and testing](../docs/development/workflow.md): running the app
  against a live backend.
- [Clients](../docs/deploy/clients.md): pointing a build at someone's
  self-hosted server, rather than developing against one.
- [Distribution](../docs/architecture/distribution.md): building APK and Linux
  packages.
