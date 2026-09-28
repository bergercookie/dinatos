# Dinatos frontend

The Flutter client for [Dinatos](../README.md)'s backend API (web today; the
same codebase targets Android and Linux desktop). See
[`../docs/architecture/frontend.md`](../docs/architecture/frontend.md) for
the app's structure, and
[`../docs/development/workflow.md`](../docs/development/workflow.md) for how
to run it against a live backend during development --
[`../docs/deploy/clients.md`](../docs/deploy/clients.md) instead if you're
pointing a build at someone's self-hosted instance rather than developing
against it.

```bash
just install
just check   # format check, flutter analyze, flutter test
just run     # flutter run -d web-server --web-port 8081, hot reload
```
