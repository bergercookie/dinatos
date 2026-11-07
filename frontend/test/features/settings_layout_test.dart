import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/core/external_link.dart';
import 'package:dinatos_frontend/core/router.dart';
import 'package:dinatos_frontend/core/server_url_provider.dart';
import 'package:dinatos_frontend/core/server_url_storage.dart';
import 'package:dinatos_frontend/features/calendar/workout_reminders.dart';
import 'package:dinatos_frontend/features/imports/hevy_import_screen.dart';
import 'package:dinatos_frontend/features/imports/intervals_import_screen.dart';
import 'package:dinatos_frontend/features/profile/import_export_screen.dart';
import 'package:dinatos_frontend/features/profile/profile_providers.dart';
import 'package:dinatos_frontend/features/profile/profile_screen.dart';
import 'package:dinatos_frontend/models/profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

/// How the Settings screen is laid out: data import/export lives on its own
/// "Import and export" screen behind one tile, and the two API-documentation
/// links are one expandable tile. Driven through the real router so a route
/// that goes missing, or a back button that lands in the wrong place, fails
/// here rather than only in a browser.
void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  Dio signedInDio() {
    final dio = buildMockDio();
    when(() => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
        .thenAnswer((invocation) async {
          final path = invocation.positionalArguments[0] as String;
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {'access_token': 'test-token'},
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
    when(() => dio.post<void>(any()))
        .thenAnswer((_) async => Response(requestOptions: RequestOptions(), statusCode: 204));
    return dio;
  }

  /// The real app and router, signed in, parked on [location].
  Future<(ProviderContainer, List<Uri>)> pumpApp(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <Uri>[];
    final container = ProviderContainer(
      overrides: [
        workoutReminderServiceProvider.overrideWithValue(NoopWorkoutReminderService()),
        serverUrlProvider.overrideWith((ref) => 'https://api.example.com'),
        serverUrlStorageProvider.overrideWithValue(ServerUrlStorage(storage: FakeSecureStore())),
        tokenStorageProvider.overrideWithValue(TokenStorage(storage: FakeSecureStore())),
        dioProvider.overrideWith((ref) => signedInDio()),
        profileProvider.overrideWith(
          (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
        ),
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.notifier).login('a@example.com', 'a-password');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: container.read(routerProvider)),
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
    return (container, opened);
  }

  String path(ProviderContainer container) => container.read(routerProvider).state.uri.path;

  Future<void> finish(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  group('Settings screen', () {
    testWidgets('has one Import and export tile and none of the moved entries', (tester) async {
      await pumpApp(tester, '/profile');

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Import and export'), findsOneWidget);
      expect(find.text('Import from Hevy'), findsNothing);
      expect(find.text('Import from Intervals.icu'), findsNothing);
      expect(find.text('Import my data'), findsNothing);
      expect(find.text('Export my data'), findsNothing);
      await finish(tester);
    });

    testWidgets('has one API documentation tile with Swagger UI and ReDoc inside', (tester) async {
      await pumpApp(tester, '/profile');

      // The two old top-level tiles are gone; one expandable parent remains.
      expect(find.text('API documentation'), findsOneWidget);
      expect(find.text('API reference'), findsNothing);
      expect(find.widgetWithText(ExpansionTile, 'API documentation'), findsOneWidget);
      // Collapsed: the sub-options are not shown yet.
      expect(find.text('Swagger UI'), findsNothing);
      expect(find.text('ReDoc'), findsNothing);

      await tester.ensureVisible(find.text('API documentation'));
      await tester.tap(find.text('API documentation'));
      await tester.pumpAndSettle();

      expect(find.text('Swagger UI'), findsOneWidget);
      expect(find.text('ReDoc'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('each API documentation sub-option opens its own page', (tester) async {
      final (container, opened) = await pumpApp(tester, '/profile');

      await tester.ensureVisible(find.text('API documentation'));
      await tester.tap(find.text('API documentation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Swagger UI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ReDoc'));
      await tester.pumpAndSettle();

      expect(opened.map((u) => u.toString()), [
        'https://api.example.com/docs',
        'https://api.example.com/redoc',
      ]);
      expect(path(container), '/profile');
      await finish(tester);
    });

    testWidgets('the Import and export tile opens the Import and export screen', (tester) async {
      final (container, _) = await pumpApp(tester, '/profile');

      await tester.ensureVisible(find.text('Import and export'));
      await tester.tap(find.text('Import and export'));
      await tester.pumpAndSettle();

      expect(path(container), '/profile/import-export');
      expect(find.byType(ImportExportScreen), findsOneWidget);
      await finish(tester);
    });
  });

  group('Import and export screen', () {
    testWidgets('lists every import and export entry', (tester) async {
      await pumpApp(tester, '/profile/import-export');

      expect(find.widgetWithText(AppBar, 'Import and export'), findsOneWidget);
      for (final entry in [
        'Import from Hevy',
        'Import from Intervals.icu',
        'Import my data',
        'Export my data',
      ]) {
        expect(find.text(entry), findsOneWidget, reason: entry);
      }
      await finish(tester);
    });

    testWidgets('the Hevy importer opens, and back returns to Import and export', (tester) async {
      final (container, _) = await pumpApp(tester, '/profile/import-export');

      await tester.tap(find.text('Import from Hevy'));
      await tester.pumpAndSettle();
      expect(path(container), '/profile/import-export/hevy');
      expect(find.byType(HevyImportScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(path(container), '/profile/import-export');
      expect(find.byType(ImportExportScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('the Intervals.icu importer opens, and back returns to Import and export', (
      tester,
    ) async {
      final (container, _) = await pumpApp(tester, '/profile/import-export');

      await tester.tap(find.text('Import from Intervals.icu'));
      await tester.pumpAndSettle();
      expect(path(container), '/profile/import-export/intervals');
      expect(find.byType(IntervalsImportScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(path(container), '/profile/import-export');
      await finish(tester);
    });

    testWidgets('back from the screen itself returns to Settings', (tester) async {
      final (container, _) = await pumpApp(tester, '/profile/import-export');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(path(container), '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('the importers keep working at their former paths', (tester) async {
      final (container, _) = await pumpApp(tester, '/profile/import-hevy');
      expect(path(container), '/profile/import-export/hevy');
      expect(find.byType(HevyImportScreen), findsOneWidget);

      container.read(routerProvider).go('/profile/import-intervals');
      await tester.pumpAndSettle();
      expect(path(container), '/profile/import-export/intervals');
      expect(find.byType(IntervalsImportScreen), findsOneWidget);
      await finish(tester);
    });
  });
}
