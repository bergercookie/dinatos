import 'package:dinatos_frontend/features/imports/hevy_import_screen.dart';
import 'package:dinatos_frontend/models/equipment.dart';
import 'package:dinatos_frontend/models/hevy_import_result.dart';
import 'package:dinatos_frontend/models/muscle_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const guessed = ImportedExercise(
    id: 7,
    name: 'Zottman Curl (Dumbbell)',
    equipment: Equipment.dumbbell,
    primaryMuscles: [MuscleGroup.biceps],
    secondaryMuscles: [MuscleGroup.forearms],
    equipmentGuessed: true,
    musclesGuessed: true,
  );
  const unknown = ImportedExercise(id: 8, name: 'Homemade Thing');

  Future<GoRouter> pump(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: ImportedExercisesReview(exercises: [guessed, unknown])),
        ),
        GoRoute(path: '/exercises', builder: (context, state) => const Text('list page')),
        GoRoute(
          path: '/exercises/:id/edit',
          builder: (context, state) => Text('edit ${state.pathParameters['id']}'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  testWidgets('says the matching was automatic and lists guessed fields', (tester) async {
    await pump(tester);

    expect(find.text('Please review 2 new custom exercises'), findsOneWidget);
    expect(find.textContaining('some guesses may be wrong'), findsOneWidget);
    expect(find.textContaining('Equipment: Dumbbell (guessed)'), findsOneWidget);
    expect(find.textContaining('Biceps, Forearms (secondary) (guessed)'), findsOneWidget);
    // Nothing guessed: shown as not set rather than as a guess.
    expect(find.textContaining('Equipment: not set'), findsOneWidget);
    expect(find.textContaining('Muscles: not set'), findsOneWidget);
  });

  testWidgets('tapping an exercise opens its edit screen', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Zottman Curl (Dumbbell)'));
    await tester.pumpAndSettle();

    expect(find.text('edit 7'), findsOneWidget);
  });

  testWidgets('the button opens the exercise list', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Open exercise list'));
    await tester.pumpAndSettle();

    expect(find.text('list page'), findsOneWidget);
  });
}
