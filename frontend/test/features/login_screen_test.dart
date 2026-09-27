import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/core/server_url_provider.dart';
import 'package:dinatos_frontend/core/server_url_storage.dart';
import 'package:dinatos_frontend/features/auth/login_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

/// Everything the login screen's own logic needs faked out: no real
/// platform channel for secure storage, and dioProvider overridden with a
/// mock so tapping "Log in" never opens a real socket (which, under
/// `flutter_test`'s fake-async zone, leaves a connection-timeout Timer
/// pending forever and fails the test on teardown) -- `dioProvider`
/// actually rebuilding from `serverUrlProvider` is covered by
/// server_url_provider_test.dart instead.
List<Override> _overrides({
  required MockDio dio,
  String initialServerUrl = 'https://initial.example.com',
}) => [
  serverUrlProvider.overrideWith((ref) => initialServerUrl),
  serverUrlStorageProvider.overrideWithValue(ServerUrlStorage(storage: FakeSecureStore())),
  tokenStorageProvider.overrideWithValue(TokenStorage(storage: FakeSecureStore())),
  dioProvider.overrideWithValue(dio),
];

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  MockDio stubbedFailingDio() {
    final dio = buildMockDio();
    when(() => dio.post<Map<String, dynamic>>('/auth/login', data: any(named: 'data')))
        .thenThrow(DioException(requestOptions: RequestOptions(path: '/auth/login')));
    return dio;
  }

  testWidgets('prefills the Server URL field from serverUrlProvider', (tester) async {
    final container = ProviderContainer(
      overrides: _overrides(dio: stubbedFailingDio(), initialServerUrl: 'https://mine.example.com'),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.widgetWithText(TextFormField, 'https://mine.example.com'), findsOneWidget);
  });

  testWidgets('logging in without touching the Server field never persists it', (tester) async {
    final container = ProviderContainer(overrides: _overrides(dio: stubbedFailingDio()));
    addTearDown(container.dispose);
    final storage = container.read(serverUrlStorageProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'a@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'a-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pump();

    expect(await storage.read(), isNull);
    expect(container.read(serverUrlProvider), 'https://initial.example.com');
  });

  testWidgets('logging in after editing the Server field persists and applies it', (tester) async {
    final container = ProviderContainer(overrides: _overrides(dio: stubbedFailingDio()));
    addTearDown(container.dispose);
    final storage = container.read(serverUrlStorageProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'https://initial.example.com'),
      'https://changed.example.com',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'a@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'a-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    // The login call itself fails against the stubbed dio -- that's fine
    // and expected: the server URL commit happens before that call, so
    // it's already applied regardless of how the login call turns out.
    await tester.pump();

    expect(await storage.read(), 'https://changed.example.com');
    expect(container.read(serverUrlProvider), 'https://changed.example.com');
  });

  testWidgets('following the Register link also commits an edited Server field', (tester) async {
    final container = ProviderContainer(overrides: _overrides(dio: stubbedFailingDio()));
    addTearDown(container.dispose);
    final storage = container.read(serverUrlStorageProvider);

    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
        GoRoute(path: '/register', builder: (context, state) => const Text('register-screen')),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'https://initial.example.com'),
      'https://changed.example.com',
    );
    await tester.tap(find.text("Don't have an account? Register"));
    await tester.pumpAndSettle();

    expect(find.text('register-screen'), findsOneWidget);
    expect(await storage.read(), 'https://changed.example.com');
    expect(container.read(serverUrlProvider), 'https://changed.example.com');
  });
}
