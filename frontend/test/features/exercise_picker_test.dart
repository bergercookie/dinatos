import 'package:dinatos_frontend/features/activities/activities_providers.dart';
import 'package:dinatos_frontend/features/exercises/exercise_picker.dart';
import 'package:dinatos_frontend/models/equipment.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/muscle_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _exercises = [
  Exercise(
    id: 1,
    name: 'Bench Press',
    equipment: Equipment.barbell,
    primaryMuscles: [MuscleGroup.chest],
    secondaryMuscles: [MuscleGroup.triceps],
  ),
  Exercise(
    id: 2,
    name: 'Squat',
    equipment: Equipment.barbell,
    primaryMuscles: [MuscleGroup.quadriceps],
  ),
  Exercise(
    id: 3,
    name: 'Dumbbell Curl',
    equipment: Equipment.dumbbell,
    primaryMuscles: [MuscleGroup.biceps],
  ),
  Exercise(id: 4, name: 'Pull-up', isCustom: false),
];

Future<Exercise?> _open(WidgetTester tester, {Map<int, int> usage = const {}}) async {
  Exercise? picked;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [exerciseUsageProvider.overrideWith((ref) async => usage)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showExercisePicker(context, exercises: _exercises);
            },
            child: const Text('Add exercise'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Add exercise'));
  await tester.pumpAndSettle();
  return picked;
}

/// The chip rows scroll horizontally and build lazily, so a chip far along
/// the row has to be scrolled into view before it can be tapped. [row] is 0
/// for the muscle row, 1 for the equipment row.
Future<void> _tapChip(WidgetTester tester, int row, String label) async {
  final chip = find.widgetWithText(FilterChip, label);
  final rows = find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal);
  await tester.scrollUntilVisible(
    chip,
    100,
    scrollable: find.descendant(of: rows.at(row), matching: find.byType(Scrollable)),
  );
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  testWidgets('matches are ordered by how often each exercise is used', (tester) async {
    await _open(tester, usage: {3: 5, 2: 2});

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    // Curl (5 uses) > Squat (2) > the never-used Bench Press.
    expect(y('Dumbbell Curl'), lessThan(y('Squat')));
    expect(y('Squat'), lessThan(y('Bench Press')));
  });

  testWidgets('a search keeps the usage order among its matches', (tester) async {
    await _open(tester, usage: {4: 9});
    await tester.enterText(find.byType(TextField), 'u');
    await tester.pump();

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    // "Squat", "Dumbbell Curl" and "Pull-up" contain a u; Pull-up is used most.
    expect(y('Pull-up'), lessThan(y('Squat')));
    expect(y('Squat'), lessThan(y('Dumbbell Curl')));
  });

  testWidgets('lists every exercise with no search term entered', (tester) async {
    await _open(tester);

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Dumbbell Curl'), findsOneWidget);
  });

  testWidgets('typing a search term filters down to matching exercises', (tester) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField), 'squ');
    await tester.pump();

    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('Dumbbell Curl'), findsNothing);
  });

  testWidgets('a search term matching nothing shows an empty state', (tester) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField), 'nonexistent');
    await tester.pump();

    expect(find.text('No matching exercises'), findsOneWidget);
  });

  testWidgets('tapping an exercise resolves the picker with it', (tester) async {
    Exercise? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [exerciseUsageProvider.overrideWith((ref) async => const {})],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showExercisePicker(context, exercises: _exercises);
              },
              child: const Text('Add exercise'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();

    expect(picked?.name, 'Squat');
  });

  testWidgets('filtering by muscle matches primary and secondary muscles', (tester) async {
    await _open(tester);

    await _tapChip(tester, 0, 'Triceps');
    await tester.pump();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);
    expect(find.text('Dumbbell Curl'), findsNothing);
  });

  testWidgets('filtering by equipment narrows the list, and combines with muscle', (tester) async {
    await _open(tester);

    await _tapChip(tester, 1, 'Barbell');
    await tester.pump();
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Dumbbell Curl'), findsNothing);

    await _tapChip(tester, 0, 'Quadriceps');
    await tester.pump();
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
  });

  testWidgets('the source chips narrow to only built-in or only custom exercises', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);
    expect(find.text('Pull-up'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Built-in'));
    await tester.pump();
    expect(find.text('Pull-up'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
    await tester.pump();
    expect(find.text('Pull-up'), findsNothing);
    expect(find.text('Squat'), findsOneWidget);
  });
}
