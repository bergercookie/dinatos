import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/activities/live/activity_summary_screen.dart';
import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/features/activities/live/live_session_storage.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fakes.dart';

/// Stands in for the device's disk, so a test can "kill the app" by building a
/// second container that restores from what the first one wrote.
class _MemoryStorage implements LiveSessionStorage {
  PersistedLiveSession? stored;

  @override
  Future<PersistedLiveSession?> read() async => stored;

  @override
  Future<void> write(PersistedLiveSession? session) async => stored = session;
}

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: '/'),
  type: DioExceptionType.connectionError,
);

DioException _rejected(int status, String detail) => DioException(
  requestOptions: RequestOptions(path: '/'),
  type: DioExceptionType.badResponse,
  response: Response(
    requestOptions: RequestOptions(path: '/'),
    statusCode: status,
    data: {'detail': detail},
  ),
);

Response<T> _ok<T>(String path, T data, {int status = 200}) => Response(
  requestOptions: RequestOptions(path: path),
  statusCode: status,
  data: data,
);

Map<String, dynamic> _savedActivity(Map<String, dynamic> body, {int id = 9}) => {
  ...body,
  'id': id,
  'description': null,
  'exercises': <dynamic>[],
};

final _finished = LiveActivitySession(
  startedAt: DateTime.utc(2026, 9, 24, 21, 13, 0, 123),
  endedAt: DateTime.utc(2026, 9, 24, 21, 54),
  routineName: 'Push day',
  exercises: const [
    ActivityExercise(
      exerciseId: 1,
      sets: [ActivitySet(weightKg: 85, reps: 5), ActivitySet(weightKg: 80, reps: 8)],
    ),
  ],
);

/// A [MockDio] for the summary screen: an empty catalog, and by default a
/// server that cannot be reached for anything else. Tests override from there.
MockDio _dio() {
  final dio = buildMockDio();
  when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
      .thenAnswer((_) async => _ok<List<dynamic>>('/exercises', []));
  when(() => dio.get<Map<String, dynamic>>('/exercises/1/records')).thenThrow(_offline());
  return dio;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required MockDio dio,
  required _MemoryStorage storage,
  PersistedLiveSession? restored,
}) async {
  // Tall enough that the Save button is on screen without scrolling.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(dio),
      liveSessionStorageProvider.overrideWithValue(storage),
      restoredLiveSessionProvider.overrideWithValue(restored),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/summary',
    routes: [
      GoRoute(path: '/summary', builder: (context, state) => const ActivitySummaryScreen()),
      GoRoute(path: '/activities', builder: (context, state) => const Text('activities list')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a workout finished offline is kept, and a retry saves it exactly once', (
    tester,
  ) async {
    final storage = _MemoryStorage();
    final dio = _dio();
    final bodies = <Map<String, dynamic>>[];
    var attempt = 0;
    when(() => dio.post<Map<String, dynamic>>('/activities', data: any(named: 'data')))
        .thenAnswer((invocation) async {
          final body = invocation.namedArguments[#data] as Map<String, dynamic>;
          bodies.add(body);
          if (++attempt == 1) throw _offline();
          return _ok('/activities', _savedActivity(body), status: 201);
        });
    final container = await _pump(
      tester,
      dio: dio,
      storage: storage,
      restored: PersistedLiveSession(session: _finished),
    );
    // Nothing needed the network for this to be on screen and saveable.
    expect(find.text('Workout summary'), findsOneWidget);
    expect(find.text('Could not check for new records without a connection.'), findsOneWidget);

    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Your workout is kept on this device'), findsOneWidget);
    final kept = container.read(liveActivityProvider)!;
    expect(kept.isSaved, isFalse);
    expect(kept.exercises.single.sets, hasLength(2));
    // ...and it is on disk too, in case the app dies before the retry.
    expect(storage.stored!.session.exercises.single.sets, hasLength(2));
    expect(storage.stored!.session.pendingTitle, 'Push day');

    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();

    expect(find.text('Workout saved'), findsOneWidget);
    expect(container.read(liveActivityProvider)!.savedActivityId, 9);
    expect(container.read(liveActivityProvider)!.pendingTitle, isNull);
    // The retry sent the very same workout -- what lets the server see it as a
    // replay of the first attempt, should that have got through after all.
    expect(bodies, hasLength(2));
    expect(bodies[1], bodies[0]);
    expect(bodies[0]['title'], 'Push day');
  });

  testWidgets('after an attempt that may have got through, the title cannot be changed', (
    tester,
  ) async {
    final dio = _dio();
    when(() => dio.post<Map<String, dynamic>>('/activities', data: any(named: 'data')))
        .thenThrow(_offline());
    await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: _finished),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.textContaining('the title is locked'), findsOneWidget);
  });

  testWidgets('a restart in that state restores the locked title and the unsaved workout', (
    tester,
  ) async {
    final dio = _dio();
    final bodies = <Map<String, dynamic>>[];
    when(() => dio.post<Map<String, dynamic>>('/activities', data: any(named: 'data')))
        .thenAnswer((invocation) async {
          final body = invocation.namedArguments[#data] as Map<String, dynamic>;
          bodies.add(body);
          return _ok('/activities', _savedActivity(body), status: 201);
        });
    // What was written to disk by the previous run, read back as at app start.
    final onDisk = PersistedLiveSession.fromJson(
      PersistedLiveSession(
        session: LiveActivitySession(
          startedAt: _finished.startedAt,
          endedAt: _finished.endedAt,
          routineName: 'Push day',
          pendingTitle: 'My own title',
          exercises: _finished.exercises,
        ),
        ownerId: 3,
      ).toJson(),
    );
    final container = await _pump(tester, dio: dio, storage: _MemoryStorage(), restored: onDisk);

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('My own title'), findsOneWidget);

    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();

    expect(bodies.single['title'], 'My own title');
    expect(bodies.single['started_at'], '2026-09-24T21:13:00.123Z');
    expect(container.read(liveActivityProvider)!.isSaved, isTrue);
  });

  testWidgets('a rejection from the server leaves the title editable and says why', (tester) async {
    final dio = _dio();
    when(() => dio.post<Map<String, dynamic>>('/activities', data: any(named: 'data')))
        .thenThrow(_rejected(422, 'routine not found'));
    final container = await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: _finished),
    );

    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();

    expect(find.text('routine not found'), findsOneWidget);
    expect(container.read(liveActivityProvider)!.pendingTitle, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('a rejection after an uncertain attempt unlocks the title again', (tester) async {
    final dio = _dio();
    var attempt = 0;
    when(() => dio.post<Map<String, dynamic>>('/activities', data: any(named: 'data')))
        .thenAnswer((_) async {
          throw ++attempt == 1 ? _offline() : _rejected(401, 'session expired');
        });
    await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: _finished),
    );

    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('an unreadable response keeps the workout and is retryable', (tester) async {
    final dio = _dio();
    when(() => dio.post<Map<String, dynamic>>('/activities', data: any(named: 'data')))
        .thenAnswer((_) async => _ok('/activities', <String, dynamic>{'oops': true}));
    final container = await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: _finished),
    );

    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Something went wrong while saving'), findsOneWidget);
    expect(container.read(liveActivityProvider)!.isSaved, isFalse);
    expect(container.read(liveActivityProvider)!.pendingTitle, 'Push day');
    expect(find.text('Save workout'), findsOneWidget);
  });

  testWidgets('an empty title is refused without calling the server', (tester) async {
    final dio = _dio();
    await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: _finished),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save workout'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    verifyNever(() => dio.post<Map<String, dynamic>>('/activities', data: any(named: 'data')));
  });

  testWidgets('records are reported when the server can be reached', (tester) async {
    final dio = _dio();
    when(
      () => dio.get<Map<String, dynamic>>('/exercises/1/records'),
    ).thenAnswer((_) async => _ok('/exercises/1/records', {'max_weight_kg': 80.0, 'max_reps': 12}));
    await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: _finished),
    );

    expect(find.text('New heaviest weight: 85.0 kg'), findsOneWidget);
    expect(find.textContaining('without a connection'), findsNothing);
  });

  testWidgets('with no new record it says so, rather than implying it could not check', (
    tester,
  ) async {
    final dio = _dio();
    when(() => dio.get<Map<String, dynamic>>('/exercises/1/records')).thenAnswer(
      (_) async => _ok('/exercises/1/records', {'max_weight_kg': 100.0, 'max_reps': 12}),
    );
    await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: _finished),
    );

    expect(find.text('No new records this time — keep at it.'), findsOneWidget);
  });

  testWidgets('Retry re-checks the records once the connection is back', (tester) async {
    final dio = _dio();
    await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: _finished),
    );
    expect(find.textContaining('without a connection'), findsOneWidget);

    when(
      () => dio.get<Map<String, dynamic>>('/exercises/1/records'),
    ).thenAnswer((_) async => _ok('/exercises/1/records', {'max_weight_kg': 80.0, 'max_reps': 12}));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('New heaviest weight: 85.0 kg'), findsOneWidget);
  });

  testWidgets('warm-ups never produce a record, and bodyweight reps do', (tester) async {
    final dio = _dio();
    when(
      () => dio.get<Map<String, dynamic>>('/exercises/1/records'),
    ).thenAnswer((_) async => _ok('/exercises/1/records', {'max_weight_kg': 80.0, 'max_reps': 10}));
    final session = LiveActivitySession(
      startedAt: DateTime.utc(2026, 9, 24, 21),
      endedAt: DateTime.utc(2026, 9, 24, 22),
      exercises: const [
        ActivityExercise(
          exerciseId: 1,
          sets: [
            ActivitySet(setType: SetType.warmup, weightKg: 200, reps: 30),
            ActivitySet(reps: 12),
          ],
        ),
      ],
    );
    await _pump(
      tester,
      dio: dio,
      storage: _MemoryStorage(),
      restored: PersistedLiveSession(session: session),
    );

    expect(find.text('New best: 12 reps'), findsOneWidget);
    expect(find.textContaining('New heaviest'), findsNothing);
  });
}
