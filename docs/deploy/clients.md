# Clients

`docker-compose.yml` (see [Quickstart](quickstart.md)) only stands up
**Postgres and the backend** -- there's no packaged frontend web container
today. Getting a client in front of your instance means one of:

## Build the Flutter web app yourself

```bash
cd frontend
flutter build web --release
```

`build/web/` is a static site: serve it with any static file server (nginx,
Caddy, `python3 -m http.server`, ...) alongside the backend, on whatever
origin you like. It asks for the backend's Server URL on first launch (see
[Getting started](../user-guide/getting-started.md)), so the same build
works no matter what URL you serve it from or what backend you point it at
-- rebuilding per-deployment isn't necessary. See
[CORS](security-and-networking.md#cors) for the one thing this needs from
the backend side.

## Use a prebuilt native client

Every tagged release publishes an Android APK and Linux `.deb`/`.AppImage`
packages -- see the
[Releases page](https://github.com/bergercookie/dinatos/releases) and
[Distribution](../architecture/distribution.md) for exactly what's built.
Install one, then point it at your instance's URL the same way as the web
build: the Server URL field on first launch, editable later from the
profile screen.

There's no packaged macOS or Windows build yet, and no iOS build (Flutter
supports the platform, but nothing in this repo builds or signs it).
