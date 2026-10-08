import 'package:dinatos_frontend/core/api_exception.dart';
import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/features/activities/live/start_activity_sheet.dart';
import 'package:dinatos_frontend/features/calendar/planned_workouts_providers.dart';
import 'package:dinatos_frontend/features/routines/routines_providers.dart';
import 'package:dinatos_frontend/features/routines/routines_repository.dart';
import 'package:dinatos_frontend/models/planned_workout.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockRoutines extends Mock implements RoutinesRepository {}

const _routine = Routine(
  id: 4,
  name: 'Push day',
  exercises: [
    RoutineExercise(exerciseId: 2, sets: [RoutineSet(targetWeightKg: 60, targetReps: 8)]),
  ],
);

PlannedWorkout _plan(int id, {required DateTime at, int? routineId, int? done}) => PlannedWorkout(
  id: id,
  title: 'Plan $id',
  scheduledAt: at,
  routineId: routineId,
  completedActivityId: done,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  List<PlannedWorkout> plans, {
  RoutinesRepository? routines,
}) async {
  final container = ProviderContainer(
    overrides: [
      plannedWorkoutListProvider.overrideWith((ref) async => plans),
      routineListProvider.overrideWith((ref) async => [_routine]),
      if (routines != null) routinesRepositoryProvider.overrideWithValue(routines),
    ],
  );
  addTearDown(container.dispose);
  // Home keeps the plans loaded; so do the same here.
  await container.read(plannedWorkoutListProvider.future);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showStartActivitySheet(context, ref),
                child: const Text('open sheet'),
              ),
            ),
          ),
        ),
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
  await tester.tap(find.text('open sheet'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  final today = DateTime.now();
  final todayAt = DateTime(today.year, today.month, today.day, 23, 30);
  final tomorrow = todayAt.add(const Duration(days: 1));

  testWidgets('offers only the two usual options when nothing is planned today', (tester) async {
    await _pump(tester, [_plan(1, at: tomorrow)]);

    expect(find.text('Use routine'), findsOneWidget);
    expect(find.text('From scratch'), findsOneWidget);
    expect(find.text('Planned workout'), findsNothing);
  });

  testWidgets('a completed plan today does not add the third option', (tester) async {
    await _pump(tester, [_plan(1, at: todayAt, done: 3)]);

    expect(find.text('Planned workout'), findsNothing);
  });

  testWidgets('a workout planned today is a third option, naming it', (tester) async {
    await _pump(tester, [_plan(1, at: todayAt)]);

    expect(find.text('Planned workout'), findsOneWidget);
    expect(find.textContaining('Plan 1'), findsOneWidget);
    expect(find.text('Use routine'), findsOneWidget);
    expect(find.text('From scratch'), findsOneWidget);
  });

  testWidgets('starting a routine-less plan begins an empty workout tied to the plan', (
    tester,
  ) async {
    final container = await _pump(tester, [_plan(7, at: todayAt)]);

    await tester.tap(find.text('Planned workout'));
    await tester.pumpAndSettle();

    expect(find.text('live screen'), findsOneWidget);
    final session = container.read(liveActivityProvider)!;
    expect(session.plannedWorkoutId, 7);
    expect(session.routineName, 'Plan 7');
    expect(session.routineId, isNull);
    expect(session.exercises, isEmpty);
  });

  testWidgets('starting a plan with a routine copies the routine and keeps the plan title', (
    tester,
  ) async {
    final routines = _MockRoutines();
    when(() => routines.get(4)).thenAnswer((_) async => _routine);
    final container = await _pump(tester, [
      _plan(8, at: todayAt, routineId: 4),
    ], routines: routines);

    await tester.tap(find.text('Planned workout'));
    await tester.pumpAndSettle();

    expect(find.text('live screen'), findsOneWidget);
    final session = container.read(liveActivityProvider)!;
    expect(session.plannedWorkoutId, 8);
    expect(session.routineId, 4);
    expect(session.routineName, 'Plan 8');
    expect(session.exercises.single.exerciseId, 2);
    expect(session.exercises.single.sets.single.reps, 8);
  });

  testWidgets('several plans today ask which one', (tester) async {
    final container = await _pump(tester, [
      _plan(1, at: DateTime(today.year, today.month, today.day, 22)),
      _plan(2, at: todayAt),
    ]);

    expect(find.text('2 planned today'), findsOneWidget);
    await tester.tap(find.text('Planned workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan 2'));
    await tester.pumpAndSettle();

    expect(container.read(liveActivityProvider)!.plannedWorkoutId, 2);
  });

  testWidgets('a routine that cannot be loaded is reported, not crashed on', (tester) async {
    final routines = _MockRoutines();
    when(() => routines.get(4)).thenThrow(const ApiException('boom'));
    final container = await _pump(tester, [
      _plan(8, at: todayAt, routineId: 4),
    ], routines: routines);

    await tester.tap(find.text('Planned workout'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not start the planned workout: boom'), findsOneWidget);
    expect(container.read(liveActivityProvider), isNull);
  });
}
