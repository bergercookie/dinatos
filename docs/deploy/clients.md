# Clients

The ways people can connect to your instance: the built-in web app, native apps, or a web build you host yourself.

## Built-in web app

The image serves the API and the web app from one address. Open it in a browser. No Server URL is needed, because the app talks to the address that served it.

## Native apps

Each tagged release publishes an Android APK and Linux `.deb` and `.AppImage` packages on the [Releases page](https://github.com/bergercookie/dinatos/releases).

1. Install the app.
2. Enter your instance address in **Server URL** on the first screen. Change it later in **Settings**.

There is no macOS, Windows or iOS build.

## Hosting the web app on its own origin

Do this only if the web app must be on a different address than the API, for example behind a CDN.

1. Build it (needs the Flutter SDK):

   ```bash
   cd frontend
   flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
   ```

2. Serve `frontend/build/web/` with any static file server.
3. Allow that origin on the backend. See [CORS](security-and-networking.md#cors).

Without `API_BASE_URL`, the build uses its own address. With it, requests go to that URL, and **Server URL** is pre-filled with it.
