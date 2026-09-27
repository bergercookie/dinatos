import 'package:flutter/services.dart';

import 'secure_store.dart';

/// Persists whether to skip TLS certificate verification for the current
/// server -- a separate key from the URL itself (see [ServerUrlStorage]),
/// since a homelab server behind a reverse proxy with a self-signed
/// certificate is a real, common setup this app is released for, and
/// without this there's no way to reach it at all short of the person
/// installing their own CA on every device.
///
/// See [TokenStorage]'s class doc for why every call here tolerates
/// `PlatformException`.
class InsecureTlsStorage {
  InsecureTlsStorage({SecureStore? storage}) : _storage = storage ?? const FlutterSecureStore();

  static const _key = 'allow_insecure_tls';

  final SecureStore _storage;

  Future<bool> read() async {
    try {
      return await _storage.read(_key) == 'true';
    } on PlatformException {
      return false;
    }
  }

  Future<void> write(bool allow) async {
    try {
      await _storage.write(_key, allow.toString());
    } on PlatformException {
      // Best-effort: see the class doc above.
    }
  }
}
