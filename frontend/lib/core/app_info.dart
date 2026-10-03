/// Build-time facts about this app, injected with `--dart-define` (see
/// `packaging/justfile`, the Dockerfile and `release.yml`); the defaults are
/// what a plain local `flutter run`/`build` gets.
const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
const String appCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: 'unknown');
const String docsUrl = 'https://bergercookie.dev/dinatos';
const String copyrightNotice = 'Copyright (c) 2026 Nikos Koukis. Released under the MIT License.';
