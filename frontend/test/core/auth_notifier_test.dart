import 'dart:async';

import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/auth_state.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  test('bootstrap resolves to AuthAuthenticated for a valid stored token', () async {
    final dio = buildMockDio();
    final tokenStorage = TokenStorage(storage: FakeSecureStore())..write('stored-token');

    when(
      () => dio.get<Map<String, dynamic>>('/auth/me', options: any(named: 'options')),
    ).thenAnswer((_) async => userResponse({'id': 1, 'email': 'a@example.com', 'is_admin': false}));

    final notifier = AuthNotifier(dio, tokenStorage);
    // _bootstrap() is fired from the constructor without being awaited --
    // pumping the microtask/timer queue is what lets it actually finish.
    await pumpEventQueue();

    expect(notifier.state, isA<AuthAuthenticated>());
  });

  test('a login racing a slow bootstrap wins -- the bootstrap does not clobber it once it finally resolves', () async {
    // This is the exact race switching servers can create: changing the
    // server URL rebuilds AuthNotifier (see dio_provider.dart), so a
    // fresh instance's own unawaited bootstrap can still be in flight
    // when the screen that triggered the switch calls login() on that
    // same fresh instance. Without the `state is AuthUnknown` guard in
    // auth_notifier.dart, whichever finished last would win -- this test
    // makes bootstrap finish last on purpose and asserts it still loses.
    final dio = buildMockDio();
    final tokenStorage = TokenStorage(storage: FakeSecureStore())..write('stored-token');
    final bootstrapGate = Completer<Response<Map<String, dynamic>>>();

    when(
      () => dio.get<Map<String, dynamic>>('/auth/me', options: any(named: 'options')),
    ).thenAnswer((invocation) {
      final options = invocation.namedArguments[#options] as Options;
      final authHeader = options.headers!['Authorization'] as String;
      if (authHeader == 'Bearer stored-token') {
        // Bootstrap's own call -- held open until the test releases it.
        return bootstrapGate.future;
      }
      // login()'s call, for the freshly-issued token.
      return Future.value(userResponse({'id': 2, 'email': 'fresh@example.com', 'is_admin': false}));
    });
    when(() => dio.post<Map<String, dynamic>>('/auth/login', data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/auth/login'),
        statusCode: 200,
        data: {'access_token': 'fresh-token'},
      ),
    );

    final notifier = AuthNotifier(dio, tokenStorage);
    // Bootstrap has started (and is now blocked on bootstrapGate) but
    // hasn't set any state yet -- login() runs concurrently with it.
    await notifier.login('fresh@example.com', 'a-password');

    expect(notifier.state, isA<AuthAuthenticated>());
    expect((notifier.state as AuthAuthenticated).token, 'fresh-token');

    // Now let the slow bootstrap call finally resolve, successfully.
    // Without the guard this overwrites `state` right back to
    // AuthAuthenticated(token: 'stored-token', ...) -- a real, if stale,
    // result, not an error, which is exactly why a plain "last write
    // wins" isn't safe here.
    bootstrapGate.complete(
      userResponse({'id': 1, 'email': 'stale@example.com', 'is_admin': false}),
    );
    await pumpEventQueue();

    expect(notifier.state, isA<AuthAuthenticated>());
    expect(
      (notifier.state as AuthAuthenticated).token,
      'fresh-token',
      reason: 'the slow bootstrap must not overwrite the already-completed login',
    );
  });
}
