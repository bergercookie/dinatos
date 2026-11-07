import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/features/routines/routines_repository.dart';
import 'package:dinatos_frontend/features/routines/start_routine_screen.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockRoutinesRepository extends Mock implements RoutinesRepository {}

const _routine = Routine(
  id: 4,
  name: 'Push day',
  exercises: [
    RoutineExercise(exerciseId: 2, sets: [RoutineSet(targetWeightKg: 60, targetReps: 8)]),
  ],
);

late _MockRoutinesRepository _repository;
late ProviderContainer _container;

Future<void> _pump(WidgetTester tester) async {
  _container = ProviderContainer(
    overrides: [routinesRepositoryProvider.overrideWithValue(_repository)],
  );
  addTearDown(_container.dispose);
  final router = GoRouter(
    initialLocation: '/routines/4/start',
    routes: [
      GoRoute(
        path: '/routines/:id/start',
        builder: (context, state) =>
            StartRoutineScreen(routineId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/routines',
        builder: (context, state) => const Scaffold(body: Text('routine list')),
      ),
      GoRoute(
        path: '/activities/live',
        builder: (context, state) => const Scaffold(body: Text('live screen')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _repository = _MockRoutinesRepository());

  testWidgets('starts a live workout from the routine straight away', (tester) async {
    when(() => _repository.get(4)).thenAnswer((_) async => _routine);

    await _pump(tester);

    expect(find.text('live screen'), findsOneWidget);
    final session = _container.read(liveActivityProvider)!;
    expect(session.routineId, 4);
    expect(session.exercises.single.exerciseId, 2);
    expect(session.exercises.single.sets.single.weightKg, 60);
  });

  testWidgets('shows a spinner while the routine loads', (tester) async {
    when(() => _repository.get(4)).thenAnswer((_) => Future.any<Routine>([]));

    _container = ProviderContainer(
      overrides: [routinesRepositoryProvider.overrideWithValue(_repository)],
    );
    addTearDown(_container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container,
        child: const MaterialApp(home: StartRoutineScreen(routineId: 4)),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a deleted routine says so and starts nothing', (tester) async {
    when(() => _repository.get(4)).thenThrow(const ApiException('not found', statusCode: 404));

    await _pump(tester);

    expect(find.textContaining('no longer exists'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(_container.read(liveActivityProvider), isNull);

    await tester.tap(find.text('Back to Routines'));
    await tester.pumpAndSettle();
    expect(find.text('routine list'), findsOneWidget);
  });

  testWidgets('another error can be retried', (tester) async {
    when(() => _repository.get(4)).thenThrow(const ApiException('server down', statusCode: 500));

    await _pump(tester);

    expect(find.textContaining('server down'), findsOneWidget);
    expect(_container.read(liveActivityProvider), isNull);

    when(() => _repository.get(4)).thenAnswer((_) async => _routine);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('live screen'), findsOneWidget);
    expect(_container.read(liveActivityProvider)!.routineId, 4);
  });

  group('with a workout already in progress', () {
    Future<void> pumpWithSessionUnderway(WidgetTester tester) async {
      when(() => _repository.get(4)).thenAnswer((_) async => _routine);
      // A workout the person is in the middle of: not the routine's.
      final container = ProviderContainer(
        overrides: [routinesRepositoryProvider.overrideWithValue(_repository)],
      );
      container.read(liveActivityProvider.notifier).start(title: 'Morning run');
      _container = container;
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/routines/4/start',
        routes: [
          GoRoute(
            path: '/routines/:id/start',
            builder: (context, state) => const StartRoutineScreen(routineId: 4),
          ),
          GoRoute(
            path: '/routines',
            builder: (context, state) => const Scaffold(body: Text('routine list')),
          ),
          GoRoute(
            path: '/activities/live',
            builder: (context, state) => const Scaffold(body: Text('live screen')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // Not pumpAndSettle: the spinner behind the dialog never stops animating.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('asks first, and "Resume current" keeps the workout untouched', (tester) async {
      await pumpWithSessionUnderway(tester);

      expect(find.text('Workout already in progress'), findsOneWidget);
      expect(_container.read(liveActivityProvider)!.routineName, 'Morning run');

      await tester.tap(find.text('Resume current'));
      await tester.pumpAndSettle();

      expect(find.text('live screen'), findsOneWidget);
      final session = _container.read(liveActivityProvider)!;
      expect(session.routineName, 'Morning run');
      expect(session.routineId, isNull);
    });

    testWidgets('"Discard and start" replaces it with the routine', (tester) async {
      await pumpWithSessionUnderway(tester);

      await tester.tap(find.text('Discard and start'));
      await tester.pumpAndSettle();

      expect(find.text('live screen'), findsOneWidget);
      expect(_container.read(liveActivityProvider)!.routineId, 4);
    });

    testWidgets('dismissing the question leaves the workout alone and goes back', (tester) async {
      await pumpWithSessionUnderway(tester);

      // Tap the barrier, outside the dialog.
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      expect(find.text('routine list'), findsOneWidget);
      final session = _container.read(liveActivityProvider)!;
      expect(session.routineName, 'Morning run');
      expect(session.routineId, isNull);
    });
  });
}
