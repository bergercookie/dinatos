import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The read/write/delete surface [TokenStorage] and [ServerUrlStorage] need
/// from secure, platform-backed key/value storage -- narrowed down from
/// [FlutterSecureStorage] itself (a concrete class, not an interface) so a
/// fake can stand in for it in tests, where the real plugin has no
/// platform channel to talk to.
abstract class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
