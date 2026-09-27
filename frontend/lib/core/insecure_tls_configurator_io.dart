import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Android and Linux desktop (this app's two native targets) route Dio's
/// requests through a real `HttpClient`, whose certificate check this
/// overrides when explicitly allowed -- for a homelab server behind a
/// reverse proxy with a self-signed certificate, which otherwise can't be
/// reached at all short of installing a CA on every device. `null` (the
/// `allow: false` case) restores the adapter's own default checking.
void configureInsecureTls(Dio dio, bool allow) {
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = allow
        ? () => HttpClient()..badCertificateCallback = (cert, host, port) => true
        : null;
  }
}
