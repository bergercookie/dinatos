/// The backend's base URL, overridable at build/run time with
/// `--dart-define=API_BASE_URL=https://...` -- e.g. for a release web build
/// served from a different origin than `docker-compose.yml`'s default.
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}
