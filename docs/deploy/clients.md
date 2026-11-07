# Clients

A client is a program that connects to your instance. You can use the built-in web app, a native app, or a web app that you host yourself.

## Built-in web app

The app container serves the API and the web app from one address. To use the web app, open that address in a browser. You do not need to set a Server URL. The web app uses the address that served it.

## Native apps

Each tagged release publishes an Android APK, a Linux `.deb` package and a Linux `.AppImage` package. Get them from the [Releases page](https://github.com/bergercookie/dinatos/releases).

1. Install the app.
2. On the first screen, enter the address of your instance in **Server URL**.

To change the address later, use **Settings**.

Dinatos has no build for macOS, Windows or iOS.

## Hosting the web app on its own origin

Do this only if the web app must be on a different address than the API. One example is a web app behind a CDN.

1. Build the web app. This needs the Flutter SDK.

   ```bash
   cd frontend
   flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
   ```

2. Serve `frontend/build/web/` with a static file server.
3. Allow the origin of the web app on the backend. See [CORS](security-and-networking.md#cors).

If you build without `API_BASE_URL`, the web app sends requests to its own address. If you set `API_BASE_URL`, the web app sends requests to that URL. It also pre-fills **Server URL** with that URL.
