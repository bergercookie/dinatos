# Dinatos frontend

The Flutter client for [Dinatos](../README.md)'s backend API (web today; the
same codebase targets Android). See
[`../docs/architecture.md`](../docs/architecture.md)'s "Frontend" section for
the app's structure, and [`../docs/getting-started.md`](../docs/getting-started.md)
for how to run it against a live backend.

```bash
just install
just check   # format check, flutter analyze, flutter test
just run     # flutter run -d web-server --web-port 8081, hot reload
```
