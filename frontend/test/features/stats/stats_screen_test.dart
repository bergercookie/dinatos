import 'package:dinatos_frontend/features/activities/activities_providers.dart';
import 'package:dinatos_frontend/features/exercises/exercises_repository.dart';
import 'package:dinatos_frontend/features/stats/stats_screen.dart';
import 'package:dinatos_frontend/features/stats/stats_summary_card.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/muscle_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExercisesRepository implements ExercisesRepository {
  @override
  Future<List<Exercise>> list({String? search, MuscleGroup? muscle, dynamic equipment}) async =>
      const [
        Exercise(id: 1, name: 'Bench Press', primaryMuscles: [MuscleGroup.chest]),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Activity _workout(DateTime start) => Activity(
  title: 'Push',
  startedAt: start,
  endedAt: start.add(const Duration(minutes: 50)),
  exercises: const [
    ActivityExercise(
      exerciseId: 1,
      sets: [ActivitySet(weightKg: 100, reps: 5), ActivitySet(weightKg: 100, reps: 5)],
    ),
  ],
);

Future<void> _pump(WidgetTester tester, List<Activity> activities) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activityListProvider.overrideWith((ref) async => activities),
        exercisesRepositoryProvider.overrideWithValue(_FakeExercisesRepository()),
      ],
      child: const MaterialApp(home: StatsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state with no activities', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Nothing to chart yet'), findsOneWidget);
  });

  testWidgets('renders the sections for a logged workout', (tester) async {
    final now = DateTime.now();
    await _pump(tester, [_workout(now.subtract(const Duration(days: 1)))]);

    expect(find.text('Workouts per week'), findsOneWidget);
    expect(find.text('Muscle distribution'), findsOneWidget);
    expect(find.text('Go-to exercises'), findsOneWidget);
    expect(find.text('50 min'), findsWidgets);
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('Bench Press'), findsWidgets);
  });

  testWidgets('range selector excludes older workouts', (tester) async {
    final old = DateTime.now().subtract(const Duration(days: 200));
    await _pump(tester, [_workout(old)]);
    // Default range is 90 days: nothing falls inside it.
    expect(find.text('No workouts in this period'), findsOneWidget);

    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('No workouts in this period'), findsNothing);
    expect(find.text('Go-to exercises'), findsOneWidget);
  });

  testWidgets('summary card shows headline numbers and opens the stats page', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatsSummaryCard(
              activities: [_workout(DateTime.now()), _workout(DateTime.now())],
              onOpenStats: () => opened = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('2'), findsWidgets);
    expect(find.text('50 min'), findsOneWidget);
    await tester.tap(find.text('All stats'));
    expect(opened, isTrue);
  });
}
