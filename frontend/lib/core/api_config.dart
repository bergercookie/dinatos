import 'package:flutter/foundation.dart' show kIsWeb;

/// The backend's base URL, overridable at build/run time with
/// `--dart-define=API_BASE_URL=https://...` -- e.g. for a web build that
/// will be served from a different origin than the backend it talks to.
///
/// Without that override, a web build defaults to whatever origin actually
/// served it (`Uri.base`, which on Flutter web is the browser's current
/// location) -- the common case for the Docker image, which serves this
/// same build from the same origin as the API (see `main.py`'s `_WebApp`),
/// so it just works with no setup. Non-web targets (Android, Linux) have no
/// serving origin to fall back to, so they keep the previous hardcoded
/// local-dev default; `serverUrlProvider`/`ServerUrlStorage` are what
/// actually points a real install at a real server, same as before -- this
/// is only ever that provider's *starting* value.
class ApiConfig {
  const ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) {
      final origin = Uri.base;
      return Uri(scheme: origin.scheme, host: origin.host, port: origin.port).toString();
    }
    return 'http://127.0.0.1:8000';
  }
}
