# Architecture

This section explains how Dinatos works and why. It is for people who
change the code.

- To run Dinatos, see [Running your own instance](../deploy/index.md).
- To use Dinatos, see [Using Dinatos](../user-guide/index.md).

Dinatos is a self-hosted workout tracker. It has a FastAPI backend with a
Postgres database. It also has a Flutter app for web and Android. The app
talks to the backend through a REST API.

Read the pages in this order:

1. [Domain model](domain-model.md): the terms and the repository layout.
2. [Backend](backend.md): the API, authentication, backup and imports.
3. [Frontend](frontend.md): the Flutter app.
4. [Distribution](distribution.md): how the project packages a release.

`AGENTS.md` and `CONTRIBUTING.md` are in the root of the repository. They
list the problems that can occur when you build and test.

```{toctree}
:maxdepth: 2

domain-model
backend
frontend
distribution
```
