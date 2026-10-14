# Architecture

How Dinatos is built and why, for people changing the code. If you only want
to run it, see [Running your own instance](../deploy/index.md); to use it, see
[Using Dinatos](../user-guide/index.md).

Dinatos is a self-hosted workout tracker: a FastAPI backend with a Postgres
database, and a Flutter app (web and Android) that talks to it over REST.

Suggested reading order:

1. [Domain model](domain-model.md): the terms and repository layout.
2. [Backend](backend.md): API, auth, backup, imports.
3. [Frontend](frontend.md): the Flutter app.
4. [Distribution](distribution.md): how releases are packaged.

Operational gotchas for building and testing live in `AGENTS.md` and
`CONTRIBUTING.md` at the repository root.

```{toctree}
:maxdepth: 2

domain-model
backend
frontend
distribution
```
