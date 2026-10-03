import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/features/routines/routine_list_screen.dart';
import 'package:dinatos_frontend/features/routines/routines_providers.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _routine = Routine(
  id: 4,
  name: 'Push day',
  exercises: [
    RoutineExercise(exerciseId: 2, sets: [RoutineSet(targetWeightKg: 60, targetReps: 8)]),
  ],
);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      routineListProvider.overrideWith((ref) async => [_routine]),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/routines',
    routes: [
      GoRoute(path: '/routines', builder: (context, state) => const RoutineListScreen()),
      GoRoute(
        path: '/routines/:id',
        builder: (context, state) => const Scaffold(body: Text('routine editor')),
      ),
      GoRoute(
        path: '/activities/live',
        builder: (context, state) => const Scaffold(body: Text('live screen')),
      ),
    ],
  );
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
  testWidgets('the play button starts a live workout from the routine', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.byTooltip('Start workout from Push day'));
    await tester.pumpAndSettle();

    expect(find.text('live screen'), findsOneWidget);
    final session = container.read(liveActivityProvider)!;
    expect(session.routineId, 4);
    expect(session.exercises.single.exerciseId, 2);
    expect(session.exercises.single.sets.single.weightKg, 60);
  });

  testWidgets('tapping the row itself still opens the routine editor', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Push day'));
    await tester.pumpAndSettle();

    expect(find.text('routine editor'), findsOneWidget);
  });

  testWidgets('a workout already in progress is kept unless the person discards it', (
    tester,
  ) async {
    final container = await _pump(tester);
    container.read(liveActivityProvider.notifier)
      ..start()
      ..addExercise(99);

    await tester.tap(find.byTooltip('Start workout from Push day'));
    await tester.pumpAndSettle();
    expect(find.text('Workout already in progress'), findsOneWidget);

    // Resume: lands on the live screen with the original workout intact.
    await tester.tap(find.text('Resume current'));
    await tester.pumpAndSettle();
    expect(find.text('live screen'), findsOneWidget);
    expect(container.read(liveActivityProvider)!.exercises.single.exerciseId, 99);
    expect(container.read(liveActivityProvider)!.routineId, isNull);
  });

  testWidgets('discarding the workout in progress replaces it with the routine', (tester) async {
    final container = await _pump(tester);
    container.read(liveActivityProvider.notifier)
      ..start()
      ..addExercise(99);

    await tester.tap(find.byTooltip('Start workout from Push day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and start'));
    await tester.pumpAndSettle();

    expect(find.text('live screen'), findsOneWidget);
    final session = container.read(liveActivityProvider)!;
    expect(session.routineId, 4);
    expect(session.exercises.single.exerciseId, 2);
  });
}
