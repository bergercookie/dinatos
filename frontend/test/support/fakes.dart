import 'package:dinatos_frontend/core/secure_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:mocktail/mocktail.dart';

/// A real in-memory stand-in for [SecureStore] -- round-trips values the
/// way the platform keyring would when it's actually available and
/// unlocked, without needing a real platform channel under `flutter test`.
class FakeSecureStore implements SecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Stands in for a keyring that isn't running or isn't unlocked -- what
/// `flutter_secure_storage` actually throws on Linux desktop in that case
/// (see TokenStorage/ServerUrlStorage's class docs), on every call.
class ThrowingSecureStore implements SecureStore {
  static final _exception = PlatformException(
    code: 'libsecret_error',
    message: 'Failed to unlock the keyring',
  );

  @override
  Future<String?> read(String key) async => throw _exception;

  @override
  Future<void> write(String key, String value) async => throw _exception;

  @override
  Future<void> delete(String key) async => throw _exception;
}

class MockDio extends Mock implements Dio {}

/// A [MockDio] with `interceptors` stubbed to a real, empty [Interceptors]
/// list -- [AuthNotifier]'s constructor adds its bearer-token interceptor
/// to whatever `Dio` it's given (see its class doc), and mocktail's `Mock`
/// otherwise returns `null` for an unstubbed getter, which that `.add(...)`
/// call then throws on.
MockDio buildMockDio() {
  final dio = MockDio();
  when(() => dio.interceptors).thenReturn(Interceptors());
  return dio;
}

Response<Map<String, dynamic>> userResponse(Map<String, dynamic> user) => Response(
  requestOptions: RequestOptions(path: '/auth/me'),
  statusCode: 200,
  data: user,
);
