# Clients

## The web app -- already there

`docker-compose.yml` (see [Quickstart](quickstart.md)) builds one image that
serves **the API and the built Flutter web app together, from the same
origin**. Open `http://127.0.0.1:8000` (or wherever you've put a reverse
proxy in front of it) in a browser and you're at the app itself -- nothing
to build or serve separately, and no Server URL to fill in first: the build
baked into the image already talks to whatever origin served it.

## Use a prebuilt native client instead

Every tagged release also publishes an Android APK and Linux
`.deb`/`.AppImage` packages -- see the
[Releases page](https://github.com/bergercookie/dinatos/releases) and
[Distribution](../architecture/distribution.md) for exactly what's built.
Install one, then point it at your instance's URL: the Server URL field on
first launch, editable later from the settings screen.

There's no packaged macOS or Windows build yet, and no iOS build (Flutter
supports the platform, but nothing in this repo builds or signs it).

## Serving the web app from its own origin instead

Some setups still want the frontend on a different origin than the backend
-- a CDN in front of static assets, or a reverse-proxy layout that can't put
both behind the same host/port. Build it yourself:

```bash
cd frontend
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
```

`build/web/` is then a static site: serve it with any static file server
(nginx, Caddy, `python3 -m http.server`, ...) on whatever origin you like.
Without `API_BASE_URL`, a web build defaults to same-origin (the image's own
setup above); with it, every request goes to that URL instead, and the
Server URL field (still editable from the login/settings screens) starts out
pre-filled with it. See [CORS](security-and-networking.md#cors) for the one
thing a split setup like this needs from the backend side that the bundled,
same-origin build doesn't.
