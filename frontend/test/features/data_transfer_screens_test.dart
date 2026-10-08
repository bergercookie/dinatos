import 'dart:typed_data';

import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/core/file_io.dart';
import 'package:dinatos_frontend/features/admin/admin_providers.dart';
import 'package:dinatos_frontend/features/admin/admin_repository.dart';
import 'package:dinatos_frontend/features/admin/admin_screen.dart';
import 'package:dinatos_frontend/features/profile/profile_providers.dart';
import 'package:dinatos_frontend/features/profile/profile_repository.dart';
import 'package:dinatos_frontend/features/profile/profile_screen.dart';
import 'package:dinatos_frontend/models/data_transfer_result.dart';
import 'package:dinatos_frontend/models/profile.dart';
import 'package:dinatos_frontend/models/user.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

final _file = FileContent('backup.json', Uint8List.fromList([123, 125]));

void main() {
  setUpAll(() {
    registerFallbackValue(_file);
    registerFallbackValue(UserImportMode.merge);
  });

  group('admin backup card', () {
    late MockAdminRepository admin;
    late MockDio dio;
    late List<FileContent> saved;
    late ProviderContainer container;
    FileContent? picked;

    Future<void> pump(WidgetTester tester) async {
      container = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(admin),
          adminUsersProvider.overrideWith(
            (ref) async => const [User(id: 1, email: 'a@example.com', isAdmin: true)],
          ),
          profileProvider.overrideWith(
            (ref) async => const Profile(heightCm: null, unitSystem: UnitSystem.metric),
          ),
          dioProvider.overrideWithValue(dio),
          tokenStorageProvider.overrideWithValue(TokenStorage(storage: FakeSecureStore())),
          fileSaverProvider.overrideWithValue((content) async {
            saved.add(content);
            return true;
          }),
          jsonFilePickerProvider.overrideWithValue(() async => picked),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AdminScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() {
      admin = MockAdminRepository();
      dio = buildMockDio();
      when(() => dio.post<void>(any()))
          .thenAnswer((_) async => Response(requestOptions: RequestOptions(path: '/auth/logout')));
      saved = [];
      picked = _file;
    });

    testWidgets('downloading saves the file and warns that it is secret', (tester) async {
      when(() => admin.downloadBackup()).thenAnswer((_) async => _file);
      await pump(tester);

      await tester.tap(find.text('Download full backup'));
      await tester.pumpAndSettle();

      expect(saved, [_file]);
      expect(find.textContaining('password hashes'), findsWidgets);
      expect(find.textContaining('saved as backup.json'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed download shows the server message and saves nothing', (tester) async {
      when(() => admin.downloadBackup()).thenThrow(const ApiException('admin access required'));
      await pump(tester);

      await tester.tap(find.text('Download full backup'));
      await tester.pumpAndSettle();

      expect(saved, isEmpty);
      expect(find.text('admin access required'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('restore needs the typed word, then uploads and keeps the session', (tester) async {
      when(
        () => admin.restoreBackup(any()),
      ).thenAnswer((_) async => const BackupRestoreResult(rows: {'users': 3}, sessionKept: true));
      await pump(tester);

      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();

      expect(find.text('Replace everything on this server?'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Replace everything');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      verifyNever(() => admin.restoreBackup(any()));

      await tester.enterText(find.byType(TextField), 'restore');
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'RESTORE');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      verify(() => admin.restoreBackup(_file)).called(1);
      expect(find.textContaining('Restored the backup (3 accounts)'), findsOneWidget);
      verifyNever(() => dio.post<void>('/auth/logout'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('restore logs the admin out when the server ended their session', (tester) async {
      when(
        () => admin.restoreBackup(any()),
      ).thenAnswer((_) async => const BackupRestoreResult(rows: {'users': 1}, sessionKept: false));
      await pump(tester);

      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'RESTORE');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Replace everything'));
      await tester.pumpAndSettle();

      verify(() => dio.post<void>('/auth/logout')).called(1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cancelling the confirmation, or the picker, restores nothing', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      picked = null;
      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      verifyNever(() => admin.restoreBackup(any()));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a rejected backup says nothing was changed', (tester) async {
      when(() => admin.restoreBackup(any())).thenThrow(const ApiException('unknown table "x"'));
      await pump(tester);

      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'RESTORE');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Replace everything'));
      await tester.pumpAndSettle();

      expect(find.textContaining('nothing was changed: unknown table "x"'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('settings: export / import my data', () {
    late MockProfileRepository repository;
    late List<FileContent> saved;
    FileContent? picked;

    Future<void> pump(WidgetTester tester) async {
      // Tall enough that the whole Data card (Hevy, Intervals.icu, export,
      // import...) is on screen without scrolling.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(
            (ref) async => const Profile(heightCm: 180, unitSystem: UnitSystem.metric),
          ),
          fileSaverProvider.overrideWithValue((content) async {
            saved.add(content);
            return true;
          }),
          jsonFilePickerProvider.overrideWithValue(() async => picked),
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
    }

    setUp(() {
      repository = MockProfileRepository();
      saved = [];
      picked = _file;
    });

    testWidgets('export saves the file', (tester) async {
      when(() => repository.exportMyData()).thenAnswer((_) async => _file);
      await pump(tester);

      await tester.tap(find.text('Export my data'));
      await tester.pumpAndSettle();

      expect(saved, [_file]);
      expect(find.textContaining('saved as backup.json'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed export is reported', (tester) async {
      when(() => repository.exportMyData()).thenThrow(const ApiException('Could not reach'));
      await pump(tester);

      await tester.tap(find.text('Export my data'));
      await tester.pumpAndSettle();

      expect(saved, isEmpty);
      expect(find.textContaining('Export failed: Could not reach'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('import defaults to merge and reports what happened', (tester) async {
      when(() => repository.importMyData(any(), any())).thenAnswer(
        (_) async => const UserImportResult(
          mode: UserImportMode.merge,
          created: ImportCounts(routines: 2),
          skipped: ImportCounts(activities: 1),
          deleted: ImportCounts(),
        ),
      );
      await pump(tester);

      await tester.tap(find.text('Import my data'));
      await tester.pumpAndSettle();
      expect(find.text('Merge'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      verify(() => repository.importMyData(_file, UserImportMode.merge)).called(1);
      expect(find.text('Imported 2 routines; skipped 1 activity already present.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('choosing replace is explicit about what is deleted', (tester) async {
      when(() => repository.importMyData(any(), any())).thenAnswer(
        (_) async => const UserImportResult(
          mode: UserImportMode.replace,
          created: ImportCounts(routines: 1),
          skipped: ImportCounts(),
          deleted: ImportCounts(routines: 4),
        ),
      );
      await pump(tester);

      await tester.tap(find.text('Import my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace my data'));
      await tester.pump();
      expect(find.textContaining('deletes ALL your routines'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Replace and import'));
      await tester.pumpAndSettle();

      verify(() => repository.importMyData(_file, UserImportMode.replace)).called(1);
      expect(find.textContaining('replaced 4 routines'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a rejected file is reported and cancelling does nothing', (tester) async {
      when(() => repository.importMyData(any(), any()))
          .thenThrow(const ApiException('That file is not valid JSON.'));
      await pump(tester);

      // Cancel at the mode dialog.
      await tester.tap(find.text('Import my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => repository.importMyData(any(), any()));

      // No file picked at all.
      picked = null;
      await tester.tap(find.text('Import my data'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      picked = _file;
      await tester.tap(find.text('Import my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('nothing was changed: That file is not valid JSON.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
