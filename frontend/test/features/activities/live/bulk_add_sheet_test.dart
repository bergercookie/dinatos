import 'package:dinatos_frontend/features/activities/live/bulk_add_sheet.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalog = [
  Exercise(id: 1, name: 'Bench Press'),
  Exercise(id: 2, name: 'Crossover Reverse Lunge'),
  Exercise(id: 3, name: 'Pull-up'),
  Exercise(id: 4, name: 'Cable Row'),
];

/// Opens the sheet from a button and records what it resolves with.
Future<List<List<Exercise>?>> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <List<Exercise>?>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                results.add(await showBulkAddSheet(context, exercises: _catalog)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('explains what to do before anything is entered', (tester) async {
    await _open(tester);

    expect(find.textContaining('1. Type your exercises'), findsOneWidget);
    expect(find.textContaining('2. Check the matches'), findsOneWidget);
    expect(find.textContaining('3. Tap the button'), findsOneWidget);
    expect(find.text('Tap and speak'), findsNothing);
    expect(find.text('Check what we understood'), findsNothing);
    // Nothing to add yet, so the button is disabled.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add exercises')).onPressed,
      isNull,
    );
  });

  testWidgets('a numbered list becomes one reviewable row per exercise', (tester) async {
    final results = await _open(tester);

    await tester.enterText(find.byType(TextField), '1 reverse lunges 2 bench press 3 zzzz');
    await tester.pumpAndSettle();

    expect(find.text('Check what we understood'), findsOneWidget);
    expect(find.text('Crossover Reverse Lunge'), findsOneWidget);
    expect(find.text('You said "reverse lunges"'), findsOneWidget);
    expect(find.text('Best guess -- please check'), findsOneWidget);
    expect(find.text('Matched'), findsOneWidget);
    expect(find.text('No match -- tap to search'), findsOneWidget);
    // The unmatched one is not ticked, so two are added.
    expect(find.text('Add 2 exercises'), findsOneWidget);

    await tester.tap(find.text('Add 2 exercises'));
    await tester.pumpAndSettle();
    expect(results.single!.map((e) => e.id), [2, 1]);
  });

  testWidgets('unticking a row leaves it out', (tester) async {
    final results = await _open(tester);
    await tester.enterText(find.byType(TextField), '1 bench press 2 pull ups');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Add 1 exercise'), findsOneWidget);

    await tester.tap(find.text('Add 1 exercise'));
    await tester.pumpAndSettle();
    expect(results.single!.map((e) => e.id), [3]);
  });

  testWidgets('tapping a row opens the picker with what was said, and the choice replaces it', (
    tester,
  ) async {
    final results = await _open(tester);
    await tester.enterText(find.byType(TextField), '1 zzzz');
    await tester.pumpAndSettle();

    await tester.tap(find.text('No exercise found'));
    await tester.pumpAndSettle();
    // The picker's own search box is prefilled with the spoken words.
    expect(find.widgetWithText(TextField, 'zzzz'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'zzzz'), 'cable');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cable Row'));
    await tester.pumpAndSettle();

    expect(find.text('Add 1 exercise'), findsOneWidget);
    await tester.tap(find.text('Add 1 exercise'));
    await tester.pumpAndSettle();
    expect(results.single!.map((e) => e.id), [4]);
  });
}
