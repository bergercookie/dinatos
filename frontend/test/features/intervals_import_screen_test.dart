import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/features/imports/intervals_import_repository.dart';
import 'package:dinatos_frontend/features/imports/intervals_import_screen.dart';
import 'package:dinatos_frontend/models/intervals_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements IntervalsImportRepository {}

const _run = IntervalsActivity(
  id: 'i100',
  name: 'Morning run',
  type: 'Run',
  durationSeconds: 1800,
  distanceKm: 5.0,
);
final _hevyTwin = IntervalsActivity(
  id: 'i101',
  name: 'Leg day (Intervals)',
  startedAt: DateTime(2026, 3, 2, 18),
  durationSeconds: 3600,
  possibleDuplicateOf: 'Leg Day',
);
const _imported = IntervalsActivity(id: 'i103', name: 'Old ride', alreadyImported: true);
const _stub = IntervalsActivity(
  id: 'i102',
  name: 'Strava thing',
  importable: false,
  unimportableReason: 'STRAVA activities are not available',
);

void main() {
  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
    when(
      () => repository.preview(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
      ),
    ).thenAnswer((_) async => [_run, _hevyTwin, _imported, _stub]);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const IntervalsImportScreen()),
        GoRoute(path: '/activities', builder: (context, state) => const Text('activities page')),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [intervalsImportRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  Future<void> fetch(WidgetTester tester, {String key = 'secret'}) async {
    await tester.enterText(find.widgetWithText(TextField, 'API key'), key);
    await tester.tap(find.text('Fetch activities'));
    await tester.pumpAndSettle();
  }

  bool checked(WidgetTester tester, String id) =>
      tester.widget<CheckboxListTile>(find.byKey(Key('intervals-$id'))).value!;

  testWidgets('needs an API key before fetching', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Fetch activities'));
    await tester.pump();

    expect(find.byKey(const Key('intervalsError')), findsOneWidget);
    verifyNever(
      () => repository.preview(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
      ),
    );
  });

  testWidgets('leaves duplicates, imported and unimportable activities unticked', (tester) async {
    await pump(tester);

    await fetch(tester);

    expect(checked(tester, 'i100'), isTrue);
    expect(checked(tester, 'i101'), isFalse);
    expect(checked(tester, 'i103'), isFalse);
    expect(checked(tester, 'i102'), isFalse);
    expect(find.textContaining('Possible duplicate of "Leg Day"'), findsOneWidget);
    expect(find.textContaining('Already imported'), findsOneWidget);
    expect(find.textContaining("Can't be imported: STRAVA"), findsOneWidget);
    expect(find.text('1 of 3 selected'), findsOneWidget);
    expect(find.text('Import 1 activity'), findsOneWidget);
  });

  testWidgets('All / None change the selection, and unimportable ones stay out', (tester) async {
    await pump(tester);
    await fetch(tester);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(checked(tester, 'i101'), isTrue);
    expect(checked(tester, 'i102'), isFalse);
    expect(find.text('Import 3 activities'), findsOneWidget);

    await tester.tap(find.text('None'));
    await tester.pump();
    expect(find.text('0 of 3 selected'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Import 0 activities'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('ticking and unticking one activity updates the count', (tester) async {
    await pump(tester);
    await fetch(tester);

    await tester.tap(find.byKey(const Key('intervals-i101')));
    await tester.pump();
    expect(find.text('2 of 3 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('intervals-i100')));
    await tester.pump();
    expect(find.text('1 of 3 selected'), findsOneWidget);
  });

  testWidgets('imports exactly the chosen ids, from the window that was fetched', (tester) async {
    when(
      () => repository.import(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
        activityIds: any(named: 'activityIds'),
        force: any(named: 'force'),
      ),
    ).thenAnswer(
      (_) async => const IntervalsImportResult(activitiesCreated: 1, exercisesCreated: 1),
    );
    await pump(tester);
    await fetch(tester);
    // Edited after fetching: must not leak into the import request.
    await tester.enterText(find.widgetWithText(TextField, 'API key'), 'changed');

    await tester.tap(find.text('Import 1 activity'));
    await tester.pumpAndSettle();

    verify(
      () => repository.import(
        athleteId: '0',
        apiKey: 'secret',
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
        activityIds: ['i100'],
        force: false,
      ),
    ).called(1);
    expect(find.textContaining('Imported 1 activity (1 new exercises)'), findsOneWidget);
    // The list is gone: importing the same selection again needs a fresh fetch.
    expect(find.byKey(const Key('intervals-i100')), findsNothing);
    await tester.tap(find.text('Open activities'));
    await tester.pumpAndSettle();
    expect(find.text('activities page'), findsOneWidget);
  });

  testWidgets('a 409 asks before importing again, and force retries', (tester) async {
    var calls = 0;
    when(
      () => repository.import(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
        activityIds: any(named: 'activityIds'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((invocation) async {
      calls++;
      if (invocation.namedArguments[#force] == true) {
        return const IntervalsImportResult(activitiesCreated: 2, exercisesCreated: 0);
      }
      throw const IntervalsAlreadyImportedException(['i100']);
    });
    await pump(tester);
    await fetch(tester);

    await tester.tap(find.text('Import 1 activity'));
    await tester.pumpAndSettle();
    expect(find.text('Already imported'), findsOneWidget);
    await tester.tap(find.text('Import again'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.textContaining('Imported 2 activities.'), findsOneWidget);
  });

  testWidgets('cancelling the already-imported dialog imports nothing more', (tester) async {
    when(
      () => repository.import(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
        activityIds: any(named: 'activityIds'),
        force: any(named: 'force'),
      ),
    ).thenThrow(const IntervalsAlreadyImportedException(['i100']));
    await pump(tester);
    await fetch(tester);

    await tester.tap(find.text('Import 1 activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verify(
      () => repository.import(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
        activityIds: any(named: 'activityIds'),
        force: false,
      ),
    ).called(1);
    expect(find.byKey(const Key('intervals-i100')), findsOneWidget);
  });

  testWidgets('a rejected key is shown instead of a list', (tester) async {
    when(
      () => repository.preview(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
      ),
    ).thenThrow(const ApiException('Intervals.icu rejected the API key or athlete id'));
    await pump(tester);

    await fetch(tester);

    expect(find.textContaining('rejected the API key'), findsOneWidget);
    expect(find.byKey(const Key('intervals-i100')), findsNothing);
  });

  testWidgets('an import failure is shown and keeps the selection', (tester) async {
    when(
      () => repository.import(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
        activityIds: any(named: 'activityIds'),
        force: any(named: 'force'),
      ),
    ).thenThrow(const ApiException('Could not reach the server.'));
    await pump(tester);
    await fetch(tester);

    await tester.tap(find.text('Import 1 activity'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach'), findsOneWidget);
    expect(checked(tester, 'i100'), isTrue);
  });

  testWidgets('an empty range says so', (tester) async {
    when(
      () => repository.preview(
        athleteId: any(named: 'athleteId'),
        apiKey: any(named: 'apiKey'),
        oldest: any(named: 'oldest'),
        newest: any(named: 'newest'),
      ),
    ).thenAnswer((_) async => []);
    await pump(tester);

    await fetch(tester);

    expect(find.text('No activities in that date range.'), findsOneWidget);
  });

  testWidgets('the "from" date can be changed', (tester) async {
    await pump(tester);

    await tester.tap(find.textContaining('From '));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
  });
}
