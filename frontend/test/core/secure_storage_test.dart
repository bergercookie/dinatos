import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/server_url_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('TokenStorage', () {
    test('round-trips a token through a working store', () async {
      final storage = TokenStorage(storage: FakeSecureStore());

      expect(await storage.read(), isNull);
      await storage.write('a-token');
      expect(await storage.read(), 'a-token');
      await storage.clear();
      expect(await storage.read(), isNull);
    });

    test('read() returns null instead of throwing when the keyring is unavailable', () async {
      final storage = TokenStorage(storage: ThrowingSecureStore());
      expect(await storage.read(), isNull);
    });

    test('write() swallows the error instead of throwing', () async {
      final storage = TokenStorage(storage: ThrowingSecureStore());
      await expectLater(storage.write('a-token'), completes);
    });

    test('clear() swallows the error instead of throwing', () async {
      final storage = TokenStorage(storage: ThrowingSecureStore());
      await expectLater(storage.clear(), completes);
    });
  });

  group('ServerUrlStorage', () {
    test('round-trips a URL through a working store', () async {
      final storage = ServerUrlStorage(storage: FakeSecureStore());

      expect(await storage.read(), isNull);
      await storage.write('https://dinatos.example.com');
      expect(await storage.read(), 'https://dinatos.example.com');
    });

    test('read() returns null instead of throwing when the keyring is unavailable', () async {
      final storage = ServerUrlStorage(storage: ThrowingSecureStore());
      expect(await storage.read(), isNull);
    });

    test('write() swallows the error instead of throwing', () async {
      final storage = ServerUrlStorage(storage: ThrowingSecureStore());
      await expectLater(storage.write('https://dinatos.example.com'), completes);
    });
  });
}
