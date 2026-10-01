import 'package:dinatos_frontend/features/exercises/exercise_picker.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _exercises = [
  Exercise(id: 1, name: 'Bench Press'),
  Exercise(id: 2, name: 'Squat'),
  Exercise(id: 3, name: 'Deadlift'),
];

Future<Exercise?> _open(WidgetTester tester) async {
  Exercise? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            picked = await showExercisePicker(context, exercises: _exercises);
          },
          child: const Text('Add exercise'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Add exercise'));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  testWidgets('lists every exercise with no search term entered', (tester) async {
    await _open(tester);

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Deadlift'), findsOneWidget);
  });

  testWidgets('typing a search term filters down to matching exercises', (tester) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField), 'squ');
    await tester.pump();

    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('Deadlift'), findsNothing);
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
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showExercisePicker(context, exercises: _exercises);
            },
            child: const Text('Add exercise'),
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
}
