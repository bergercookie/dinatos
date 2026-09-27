import 'package:dio/dio.dart';

/// The web target can't skip TLS certificate verification from Dio at all
/// -- the browser owns the TLS handshake entirely and gives Dart no hook
/// into it, so this is a no-op there. The UI toggle still exists (it's
/// meaningless to hide it per-platform), it just doesn't do anything on
/// web; see insecure_tls_configurator_io.dart for the real, native version.
void configureInsecureTls(Dio dio, bool allow) {}
