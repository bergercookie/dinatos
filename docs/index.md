# Dinatos

A self-hosted workout tracker: exercises, workouts, and the activities you
log against them. Inspired by Hevy, built to run on your own homelab.

This site has three parts, for three different reasons to be here:

- **[Using Dinatos](user-guide/index.md)** -- you already have access to a
  running instance (someone else's, or your own) and want to log workouts,
  track measurements, or import your history from Hevy.
- **[Running your own instance](deploy/index.md)** -- you want to self-host
  Dinatos: Docker Compose, configuration, upgrades and backups, networking.
- **Contributing** -- you want to change the code itself:
  [development workflow](development/index.md) (environment setup, testing,
  CI, releases) and [architecture](architecture/index.md) (the domain model,
  and why the backend and frontend are built the way they are).

```{toctree}
:caption: Using Dinatos
:maxdepth: 2

user-guide/index
```

```{toctree}
:caption: Running your own instance
:maxdepth: 2

deploy/index
```

```{toctree}
:caption: Contributing
:maxdepth: 2

development/index
architecture/index
```
