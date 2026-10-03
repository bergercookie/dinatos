import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/auth_state.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/core/server_url_provider.dart';
import 'package:dinatos_frontend/core/server_url_storage.dart';
import 'package:dinatos_frontend/features/profile/profile_providers.dart';
import 'package:dinatos_frontend/features/profile/profile_screen.dart';
import 'package:dinatos_frontend/models/profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  /// dioProvider, overridden to still rebuild per [serverUrlProvider] change
  /// exactly like the real one does (a fresh mock "pointed at" whatever
  /// `baseUrl` is current when it's built) -- but backed by mocktail
  /// instead of a real `Dio`/`HttpClientAdapter`. A real one, even with a
  /// trivial custom adapter, reliably hangs forever inside `testWidgets`'
  /// fake-async zone (confirmed with a minimal repro outside this feature
  /// entirely); mocktail's stubs resolve through plain microtasks, which
  /// don't have that problem. This is what makes "logout hits the old
  /// baseUrl, not the new one" a real, checkable assertion rather than a
  /// foregone conclusion.
  Override recordingDioOverride(List<String> calls) {
    return dioProvider.overrideWith((ref) {
      final baseUrl = ref.watch(serverUrlProvider);
      final dio = buildMockDio();
      // logout() calls `post<void>('/auth/logout')` with no `data:` --
      // a distinct stub from the one below, since mocktail dispatches on
      // the generic type parameter too.
      when(() => dio.post<void>(any())).thenAnswer((invocation) async {
        final path = invocation.positionalArguments[0] as String;
        calls.add('POST $baseUrl$path');
        return Response(requestOptions: RequestOptions(path: path), statusCode: 204);
      });
      when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenAnswer((invocation) async {
            final path = invocation.positionalArguments[0] as String;
            calls.add('POST $baseUrl$path');
            return switch (path) {
              '/auth/login' => Response(
                requestOptions: RequestOptions(path: path),
                statusCode: 200,
                data: {'access_token': 'test-token'},
              ),
              _ => Response(requestOptions: RequestOptions(path: path), statusCode: 204),
            };
          });
      when(() => dio.get<Map<String, dynamic>>(any(), options: any(named: 'options')))
          .thenAnswer((invocation) async {
            final path = invocation.positionalArguments[0] as String;
            calls.add('GET $baseUrl$path');
            return Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 200,
              data: {'id': 1, 'email': 'a@example.com', 'is_admin': false},
            );
          });
      return dio;
    });
  }

  testWidgets(
    'changing the server logs out against the old server first, then persists and applies the new one',
    (tester) async {
      final calls = <String>[];
      final container = ProviderContainer(
        overrides: [
          serverUrlProvider.overrideWith((ref) => 'https://old.example.com'),
          serverUrlStorageProvider.overrideWithValue(ServerUrlStorage(storage: FakeSecureStore())),
          tokenStorageProvider.overrideWithValue(TokenStorage(storage: FakeSecureStore())),
          recordingDioOverride(calls),
          profileProvider.overrideWith(
            (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Reach AuthAuthenticated through the notifier's real public API
      // (not by poking `.state` from outside, which `@protected` and
      // `flutter analyze` both frown on) -- logout() needs a real session
      // to revoke in the first place.
      await container.read(authNotifierProvider.notifier).login('a@example.com', 'a-password');
      expect(container.read(authNotifierProvider), isA<AuthAuthenticated>());
      calls.clear();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('https://old.example.com'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.edit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Server URL'),
        'https://new.example.com',
      );
      // Scoped to the dialog -- the profile form below it has its own,
      // unrelated "Save" button.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pump();
      // A big, explicit pump rather than pumpAndSettle(): this blows straight
      // through the dialog's exit-transition duration in one deterministic
      // step, rather than pumpAndSettle's own repeated-short-pump heuristic
      // -- which, empirically, doesn't reliably finish the dialog's
      // AnimatedDefaultTextStyle/Overlay teardown before this test's
      // assertions run, when this file executes back-to-back with certain
      // other test files under the same `flutter_tester` binding.
      await tester.pump(const Duration(seconds: 1));

      expect(
        calls,
        contains('POST https://old.example.com/auth/logout'),
        reason: 'logout must still target the server the session actually belongs to',
      );
      expect(
        calls.any((call) => call.contains('new.example.com')),
        isFalse,
        reason: 'nothing should have been sent to the new server during this exchange',
      );
      expect(container.read(authNotifierProvider), isA<AuthUnauthenticated>());
      expect(container.read(serverUrlProvider), 'https://new.example.com');
      expect(await container.read(serverUrlStorageProvider).read(), 'https://new.example.com');

      // Unmount the tree ourselves, before `addTearDown(container.dispose)`
      // runs: flutter_test's own automatic between-tests teardown otherwise
      // races it, and disposing every provider out from under a widget that
      // hasn't actually been unmounted yet is exactly the kind of dangling
      // reference this session already hit once with a bare
      // TextEditingController (see profile_screen.dart's _ServerUrlDialog).
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancelling the dialog changes nothing', (tester) async {
    final calls = <String>[];
    final container = ProviderContainer(
      overrides: [
        serverUrlProvider.overrideWith((ref) => 'https://old.example.com'),
        serverUrlStorageProvider.overrideWithValue(ServerUrlStorage(storage: FakeSecureStore())),
        tokenStorageProvider.overrideWithValue(TokenStorage(storage: FakeSecureStore())),
        recordingDioOverride(calls),
        profileProvider.overrideWith(
          (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authNotifierProvider.notifier).login('a@example.com', 'a-password');
    calls.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Server URL'), 'https://new.example.com');
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    // See the previous test's comment on why this isn't pumpAndSettle().
    await tester.pump(const Duration(seconds: 1));

    expect(calls, isEmpty);
    expect(container.read(authNotifierProvider), isA<AuthAuthenticated>());
    expect(container.read(serverUrlProvider), 'https://old.example.com');

    // See the previous test's comment on why this has to happen before
    // `addTearDown(container.dispose)` fires.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saving a WorkoutX key patches only that field', (tester) async {
    final dio = buildMockDio();
    Map<String, dynamic>? sent;
    when(() => dio.patch<Map<String, dynamic>>(any(), data: any(named: 'data')))
        .thenAnswer((invocation) async {
          sent = invocation.namedArguments[#data] as Map<String, dynamic>;
          return Response(
            requestOptions: RequestOptions(path: '/profile'),
            statusCode: 200,
            data: {'height_cm': 180.0, 'unit_system': 'metric', 'has_workoutx_api_key': true},
          );
        });
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        profileProvider.overrideWith(
          (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The list is lazy, so the tile may not be built until scrolled to.
    await tester.scrollUntilVisible(find.text('WorkoutX API key'), 200);
    expect(find.text('Not set -- using the built-in exercise images'), findsOneWidget);
    await tester.tap(find.text('WorkoutX API key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'API key'), ' wx_secret ');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')));
    await tester.pumpAndSettle();

    expect(sent, {'workoutx_api_key': 'wx_secret'});
    await tester.pumpWidget(const SizedBox());
  });
}
