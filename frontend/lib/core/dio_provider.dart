import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'insecure_tls_configurator.dart';
import 'insecure_tls_provider.dart';
import 'local/local_api_adapter.dart';
import 'local/local_api_provider.dart';
import 'local/local_mode.dart';
import 'server_url_provider.dart';

/// Just the HTTP client, with TLS behavior applied -- the bearer-token
/// interceptor lives on [AuthNotifier] instead (see its constructor), not
/// here. It needs to read [AuthNotifier]'s own state on every request, and
/// this provider is one of *that* provider's dependencies (`AuthNotifier`
/// is built from `ref.watch(dioProvider)`): an interceptor here reading
/// `authNotifierProvider` back would close a dio -> auth -> dio cycle,
/// which Riverpod rejects with a `CircularDependencyError` -- surfacing to
/// a person as a generic "Unexpected error." on their very first login (no
/// stored token yet means `_bootstrap` never made a request, so the first
/// request ever sent through this client is the login POST itself).
/// `AuthNotifier` already holds this same `Dio` instance directly, so it
/// can add its own interceptor without going through `ref` at all.
final dioProvider = Provider<Dio>((ref) {
  if (ref.watch(localModeProvider)) {
    // No server: the same client, answered on the device (see LocalApi).
    return Dio(BaseOptions(baseUrl: 'http://local.invalid'))
      ..httpClientAdapter = LocalApiAdapter(ref.watch(localApiProvider));
  }
  final dio = Dio(BaseOptions(baseUrl: ref.watch(serverUrlProvider)));
  configureInsecureTls(dio, ref.watch(allowInsecureTlsProvider));
  return dio;
});
