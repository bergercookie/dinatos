import 'package:flutter/services.dart';

import '../secure_store.dart';

/// The session token is the only thing worth persisting (see
/// docs/architecture.md's "Authentication" section) -- it's opaque to the
/// client either way, so all this needs to survive an app restart is the
/// token itself, until it expires, is revoked (logout, here or elsewhere),
/// or the API otherwise rejects it.
///
/// On Linux desktop, the underlying storage is the system keyring
/// (libsecret) -- one that isn't running, or isn't unlocked (common outside
/// a full GNOME/KDE session: many window-manager-only or headless setups
/// never start one), makes every call here throw `PlatformException`
/// instead of just returning null. Every method treats that the same as
/// "nothing stored"/"couldn't persist" rather than letting it propagate: a
/// `read()` that threw during `main()`'s startup used to crash the app
/// before `runApp()` ever ran, on exactly the kind of minimal Linux desktop
/// this app is released for.
class TokenStorage {
  TokenStorage({SecureStore? storage}) : _storage = storage ?? const FlutterSecureStore();

  static const _tokenKey = 'access_token';

  final SecureStore _storage;

  Future<String?> read() async {
    try {
      return await _storage.read(_tokenKey);
    } on PlatformException {
      return null;
    }
  }

  Future<void> write(String token) async {
    try {
      await _storage.write(_tokenKey, token);
    } on PlatformException {
      // Best-effort, same reasoning as the class doc above: staying logged
      // in for this session beats crashing, even though it won't survive a
      // restart if the keyring really can't store it.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(_tokenKey);
    } on PlatformException {
      // Best-effort.
    }
  }
}
