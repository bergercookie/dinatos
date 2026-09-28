import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/core/router.dart';
import 'package:dinatos_frontend/core/server_url_provider.dart';
import 'package:dinatos_frontend/core/server_url_storage.dart';
import 'package:dinatos_frontend/features/docs/api_docs_screen.dart';
import 'package:dinatos_frontend/features/profile/profile_providers.dart';
import 'package:dinatos_frontend/features/profile/profile_screen.dart';
import 'package:dinatos_frontend/main.dart';
import 'package:dinatos_frontend/models/profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

/// The `/docs` route has to survive two things that are easy to break and
/// invisible in a unit test of the screen alone: a router table that stops
/// including it, and the global auth redirect (which sends anything that
/// isn't `/login` or `/register` back to the login screen when signed out).
void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  Dio loggedInDio() {
    final dio = buildMockDio();
    when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
        .thenAnswer((invocation) async {
          final path = invocation.positionalArguments[0] as String;
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'access_token': 'test-token',
              'user': {'id': 1, 'email': 'a@example.com'},
            },
          );
        });
    when(() => dio.get<Map<String, dynamic>>(any(), options: any(named: 'options')))
        .thenAnswer((invocation) async {
          final path = invocation.positionalArguments[0] as String;
          if (path == '/auth/me') {
            return userResponse(const {'id': 1, 'email': 'a@example.com', 'is_admin': false});
          }
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {'id': 1, 'email': 'a@example.com', 'unit_system': 'metric'},
          );
        });
    when(
      () => dio.post<void>(any()),
    ).thenAnswer((invocation) async => Response(requestOptions: RequestOptions(), statusCode: 204));
    return dio;
  }

  ProviderContainer signedInContainer() {
    return ProviderContainer(
      overrides: [
        serverUrlProvider.overrideWith((ref) => 'https://api.example.com'),
        serverUrlStorageProvider.overrideWithValue(ServerUrlStorage(storage: FakeSecureStore())),
        tokenStorageProvider.overrideWithValue(TokenStorage(storage: FakeSecureStore())),
        dioProvider.overrideWith((ref) => loggedInDio()),
        profileProvider.overrideWith(
          (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
        ),
      ],
    );
  }

  testWidgets('/docs renders the documentation screen when signed in', (tester) async {
    final container = signedInContainer();
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.notifier).login('a@example.com', 'a-password');

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DinatosApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/docs');
    await tester.pumpAndSettle();

    expect(find.byType(ApiDocsScreen), findsOneWidget);
    expect(find.text('https://api.example.com/docs'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('/docs is behind the same auth redirect as every other screen', (tester) async {
    // The docs describe the API this app talks to; they are not public
    // documentation, so an unauthenticated visitor gets the login screen
    // rather than a read-only view of the schema. Pinned here because the
    // redirect is a single `if` in router.dart, and adding an exemption to it
    // is exactly the kind of small change that should have to update a test.
    final container = ProviderContainer(
      overrides: [
        serverUrlStorageProvider.overrideWithValue(ServerUrlStorage(storage: FakeSecureStore())),
        tokenStorageProvider.overrideWithValue(TokenStorage(storage: FakeSecureStore())),
        dioProvider.overrideWith((ref) => loggedInDio()),
        profileProvider.overrideWith(
          (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DinatosApp()),
    );
    await tester.pumpAndSettle();

    container.read(routerProvider).go('/docs');
    await tester.pumpAndSettle();

    expect(find.byType(ApiDocsScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the profile screen links to it', (tester) async {
    final container = signedInContainer();
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.notifier).login('a@example.com', 'a-password');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: container.read(routerProvider)),
      ),
    );
    await tester.pumpAndSettle();

    // The router starts at /exercises, so go where the link actually lives.
    container.read(routerProvider).go('/profile');
    await tester.pumpAndSettle();

    expect(find.text('API documentation'), findsOneWidget);
    await tester.tap(find.text('API documentation'));
    await tester.pumpAndSettle();

    expect(find.byType(ApiDocsScreen), findsOneWidget);
    // Navigated with `go`, so the shell is replaced rather than covered -- and
    // the route has to be a real, addressable location, not just a widget
    // swap: the whole point of putting this at /docs is that the URL is
    // linkable and survives a reload.
    expect(find.byType(ProfileScreen), findsNothing);
    expect(container.read(routerProvider).state.uri.path, '/docs');

    // `go` leaves nothing to pop, so the screen has to offer its own way out
    // -- without this the docs page is a dead end.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, '/profile');

    await tester.pumpWidget(const SizedBox());
  });
}
