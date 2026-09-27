import 'package:flutter/services.dart';

import 'secure_store.dart';

/// Persists the backend's base URL across restarts, the same mechanism as
/// [TokenStorage] but a separate key -- switching servers and being logged
/// out are two different facts (see [serverUrlProvider]), so they're stored
/// independently rather than as one blob.
///
/// See [TokenStorage]'s class doc for why every call here tolerates
/// `PlatformException`: on Linux desktop this is backed by the system
/// keyring, which isn't always running or unlocked, and `read()` is called
/// from `main()` before `runApp()` -- letting that throw crashed the app
/// before it ever showed a window.
class ServerUrlStorage {
  ServerUrlStorage({SecureStore? storage}) : _storage = storage ?? const FlutterSecureStore();

  static const _serverUrlKey = 'server_url';

  final SecureStore _storage;

  Future<String?> read() async {
    try {
      return await _storage.read(_serverUrlKey);
    } on PlatformException {
      return null;
    }
  }

  Future<void> write(String url) async {
    try {
      await _storage.write(_serverUrlKey, url);
    } on PlatformException {
      // Best-effort: see the class doc above.
    }
  }
}
