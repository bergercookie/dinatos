import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/activities/widgets/activity_exercise_card.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/equipment.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/muscle_group.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fakes.dart';

Response<List<dynamic>> _exercisesResponse(List<Map<String, dynamic>> items) => Response(
  requestOptions: RequestOptions(path: '/exercises'),
  statusCode: 200,
  data: items,
);

Widget _card(Exercise catalog) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: ActivityExerciseCard(
        exercise: const ActivityExercise(exerciseId: 1, sets: [ActivitySet(uid: 1)]),
        catalogExercise: catalog,
        onChanged: (_) {},
        onRemove: () {},
      ),
    ),
  ),
);

void main() {
  _collapsibleTests();

  testWidgets('a duration-only exercise shows a duration field, not weight or reps', (
    tester,
  ) async {
    await tester.pumpWidget(
      _card(
        const Exercise(
          id: 1,
          name: 'Plank',
          tracksWeight: false,
          tracksReps: false,
          tracksDuration: true,
        ),
      ),
    );
    expect(find.widgetWithText(TextField, 'sec'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'reps'), findsNothing);
    expect(find.widgetWithText(TextField, 'kg'), findsNothing);
  });

  testWidgets('a distance + duration exercise shows both fields', (tester) async {
    await tester.pumpWidget(
      _card(
        const Exercise(
          id: 1,
          name: 'Run',
          tracksWeight: false,
          tracksReps: false,
          tracksDistance: true,
          tracksDuration: true,
        ),
      ),
    );
    expect(find.widgetWithText(TextField, 'km'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'sec'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'reps'), findsNothing);
  });

  testWidgets('a default exercise still shows weight and reps only', (tester) async {
    await tester.pumpWidget(_card(const Exercise(id: 1, name: 'Bench Press')));
    expect(find.widgetWithText(TextField, 'kg'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'reps'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'sec'), findsNothing);
  });

  testWidgets("tapping an exercise's equipment chip lists other exercises using it", (
    tester,
  ) async {
    final dio = MockDio();
    when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
        .thenAnswer((invocation) async {
          final params = invocation.namedArguments[#queryParameters] as Map;
          if (params['equipment'] == 'barbell') {
            return _exercisesResponse([
              {
                'id': 5,
                'name': 'Bench Press',
                'tracks_weight': true,
                'tracks_reps': true,
                'tracks_distance': false,
                'tracks_duration': false,
                'is_custom': true,
                'equipment': 'barbell',
                'primary_muscles': ['chest'],
                'secondary_muscles': [],
              },
              {
                'id': 6,
                'name': 'Squat (Barbell)',
                'tracks_weight': true,
                'tracks_reps': true,
                'tracks_distance': false,
                'tracks_duration': false,
                'is_custom': true,
                'equipment': 'barbell',
                'primary_muscles': [],
                'secondary_muscles': [],
              },
            ]);
          }
          return _exercisesResponse([]);
        });
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ActivityExerciseCard(
              exercise: const ActivityExercise(exerciseId: 5),
              catalogExercise: const Exercise(
                id: 5,
                name: 'Bench Press',
                equipment: Equipment.barbell,
                primaryMuscles: [MuscleGroup.chest],
              ),
              onChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Barbell'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);

    await tester.tap(find.text('Barbell'));
    await tester.pumpAndSettle();

    expect(find.text('Uses Barbell'), findsOneWidget);
    expect(find.text('Squat (Barbell)'), findsOneWidget);
  });

  testWidgets("tapping an exercise's muscle chip lists other exercises training it", (
    tester,
  ) async {
    final dio = MockDio();
    when(() => dio.get<List<dynamic>>('/exercises', queryParameters: any(named: 'queryParameters')))
        .thenAnswer((invocation) async {
          final params = invocation.namedArguments[#queryParameters] as Map;
          if (params['muscle'] == 'chest') {
            return _exercisesResponse([
              {
                'id': 7,
                'name': 'Cable Fly',
                'tracks_weight': true,
                'tracks_reps': true,
                'tracks_distance': false,
                'tracks_duration': false,
                'is_custom': true,
                'equipment': 'cable',
                'primary_muscles': ['chest'],
                'secondary_muscles': [],
              },
            ]);
          }
          return _exercisesResponse([]);
        });
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ActivityExerciseCard(
              exercise: const ActivityExercise(exerciseId: 5),
              catalogExercise: const Exercise(
                id: 5,
                name: 'Bench Press',
                primaryMuscles: [MuscleGroup.chest],
              ),
              onChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();

    expect(find.text('Trains Chest'), findsOneWidget);
    expect(find.text('Cable Fly'), findsOneWidget);
  });

  testWidgets('shows no chips at all when the exercise has no equipment or muscles', (
    tester,
  ) async {
    final dio = MockDio();
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ActivityExerciseCard(
              exercise: const ActivityExercise(exerciseId: 1),
              catalogExercise: const Exercise(id: 1, name: 'Plank'),
              onChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);
  });

  _cardTests();
}

/// A card whose edits are applied to a held [ActivityExercise], as a screen would.
class _Harness extends StatefulWidget {
  const _Harness({required this.initial, this.catalog, this.onLinkWithNext, this.supersetLabel});

  final ActivityExercise initial;
  final Exercise? catalog;
  final VoidCallback? onLinkWithNext;
  final String? supersetLabel;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late ActivityExercise exercise = widget.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ActivityExerciseCard(
          exercise: exercise,
          catalogExercise: widget.catalog ?? const Exercise(id: 5, name: 'Bench Press'),
          supersetLabel: widget.supersetLabel,
          onLinkWithNext: widget.onLinkWithNext,
          onChanged: (updated) => setState(() => exercise = updated),
          onRemove: () {},
        ),
      ),
    ),
  );
}

_HarnessState _state(WidgetTester tester) => tester.state<_HarnessState>(find.byType(_Harness));

void _cardTests() {
  group('set rows', () {
    testWidgets('tapping the set type steps warm-up > normal > drop set > failure', (tester) async {
      await tester.pumpWidget(
        const _Harness(initial: ActivityExercise(exerciseId: 5, sets: [ActivitySet()])),
      );
      expect(_state(tester).exercise.sets.single.setType, SetType.normal);

      Future<void> tapType() async {
        await tester.tap(find.bySemanticsLabel(RegExp('Set type')));
        await tester.pump();
      }

      final seen = <SetType>[];
      for (var i = 0; i < 5; i++) {
        await tapType();
        seen.add(_state(tester).exercise.sets.single.setType);
      }
      expect(seen, [
        SetType.dropset,
        SetType.failure,
        SetType.warmup,
        SetType.normal,
        SetType.dropset,
      ]);
    });

    testWidgets('the set options menu no longer lists set types', (tester) async {
      await tester.pumpWidget(
        const _Harness(initial: ActivityExercise(exerciseId: 5, sets: [ActivitySet()])),
      );
      await tester.tap(find.byTooltip('Set options'));
      await tester.pumpAndSettle();
      expect(find.text('Remove set'), findsOneWidget);
      expect(find.text('dropset'), findsNothing);
      expect(find.text('warmup'), findsNothing);
    });

    testWidgets('there is no RPE field', (tester) async {
      await tester.pumpWidget(
        const _Harness(initial: ActivityExercise(exerciseId: 5, sets: [ActivitySet()])),
      );
      expect(find.widgetWithText(TextField, 'RPE'), findsNothing);
      expect(find.widgetWithText(TextField, 'kg'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'reps'), findsOneWidget);
    });

    testWidgets('a field takes digits only, and reps no decimal point', (tester) async {
      await tester.pumpWidget(
        const _Harness(initial: ActivityExercise(exerciseId: 5, sets: [ActivitySet()])),
      );

      await tester.enterText(find.widgetWithText(TextField, 'kg'), '62.5kg');
      await tester.enterText(find.widgetWithText(TextField, 'reps'), '8.5');
      await tester.pump();

      expect(_state(tester).exercise.sets.single.weightKg, 62.5);
      expect(_state(tester).exercise.sets.single.reps, 85);
    });

    testWidgets('a body-weight exercise has no plate calculator and no weight field', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(
          initial: ActivityExercise(exerciseId: 5, sets: [ActivitySet()]),
          catalog: Exercise(id: 5, name: 'Push-up', equipment: Equipment.bodyOnly),
        ),
      );
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'kg')).enabled, isFalse);

      await tester.tap(find.byTooltip('Set options'));
      await tester.pumpAndSettle();

      expect(find.text('Plate calculator'), findsNothing);
      expect(find.text('Remove set'), findsOneWidget);
    });

    testWidgets('the plate calculator opens on the set weight', (tester) async {
      await tester.pumpWidget(
        const _Harness(
          initial: ActivityExercise(exerciseId: 5, sets: [ActivitySet(weightKg: 100)]),
        ),
      );

      await tester.tap(find.byTooltip('Set options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plate calculator'));
      await tester.pumpAndSettle();

      expect(find.text('Plate calculator'), findsOneWidget);
      expect(find.text('25 + 15'), findsOneWidget); // (100 - 20) / 2 = 40 per side
    });
  });

  group('notes and options', () {
    testWidgets('a note is added from the menu and recorded, and clearing it removes it', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness(initial: ActivityExercise(exerciseId: 5)));
      expect(find.widgetWithText(TextFormField, 'Note'), findsNothing);

      await tester.tap(find.byTooltip('Exercise options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Note'), 'pause at the bottom');
      expect(_state(tester).exercise.notes, 'pause at the bottom');

      await tester.enterText(find.widgetWithText(TextFormField, 'Note'), '');
      expect(_state(tester).exercise.notes, isNull);
    });

    testWidgets('an exercise that already has a note shows it', (tester) async {
      await tester.pumpWidget(
        const _Harness(initial: ActivityExercise(exerciseId: 5, notes: 'slow negatives')),
      );

      expect(find.text('slow negatives'), findsOneWidget);
    });

    testWidgets('superset and move entries appear only when they can apply', (tester) async {
      await tester.pumpWidget(const _Harness(initial: ActivityExercise(exerciseId: 5)));

      await tester.tap(find.byTooltip('Exercise options'));
      await tester.pumpAndSettle();

      expect(find.text('Superset with next exercise'), findsNothing);
      expect(find.text('Move up'), findsNothing);
      expect(find.text('Move down'), findsNothing);
      expect(find.text('View progress'), findsNothing);
      expect(find.text('Remove from superset'), findsNothing);
      expect(find.text('Add note'), findsOneWidget);
    });

    testWidgets('the superset entry calls back', (tester) async {
      var linked = 0;
      await tester.pumpWidget(
        _Harness(initial: const ActivityExercise(exerciseId: 5), onLinkWithNext: () => linked++),
      );

      await tester.tap(find.byTooltip('Exercise options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Superset with next exercise'));
      await tester.pumpAndSettle();

      expect(linked, 1);
    });

    testWidgets('a superset member shows its label', (tester) async {
      await tester.pumpWidget(
        const _Harness(initial: ActivityExercise(exerciseId: 5), supersetLabel: 'B'),
      );

      expect(find.text('Superset B'), findsOneWidget);
    });
  });
}

void _collapsibleTests() {
  Widget collapsible({bool enabled = true, List<ActivitySet>? sets}) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ActivityExerciseCard(
          collapsible: enabled,
          exercise: ActivityExercise(
            exerciseId: 1,
            sets:
                sets ??
                const [
                  ActivitySet(uid: 1, weightKg: 60, reps: 5, completed: true),
                  ActivitySet(uid: 2, weightKg: 60, reps: 5, completed: false),
                  ActivitySet(uid: 3, completed: false),
                ],
          ),
          catalogExercise: const Exercise(id: 1, name: 'Bench Press'),
          onChanged: (_) {},
          onRemove: () {},
        ),
      ),
    ),
  );

  group('collapsible', () {
    testWidgets('collapses to a summary and expands again', (tester) async {
      await tester.pumpWidget(collapsible());
      expect(find.text('Add set'), findsOneWidget);
      expect(find.byType(ActivitySetRow), findsNWidgets(3));

      await tester.tap(find.byTooltip('Collapse exercise'));
      await tester.pump();
      expect(find.text('Add set'), findsNothing);
      expect(find.byType(ActivitySetRow), findsNothing);
      expect(find.text('1 of 3 sets done'), findsOneWidget);
      expect(find.text('Bench Press'), findsOneWidget);

      await tester.tap(find.byTooltip('Expand exercise'));
      await tester.pump();
      expect(find.byType(ActivitySetRow), findsNWidgets(3));
      expect(find.byKey(const Key('collapsedSummary')), findsNothing);
    });

    testWidgets('tapping the title toggles it too', (tester) async {
      await tester.pumpWidget(collapsible());

      await tester.tap(find.text('Bench Press'));
      await tester.pump();
      expect(find.byKey(const Key('collapsedSummary')), findsOneWidget);
      await tester.tap(find.text('Bench Press'));
      await tester.pump();
      expect(find.byKey(const Key('collapsedSummary')), findsNothing);
    });

    testWidgets('summary wording for none and one set', (tester) async {
      await tester.pumpWidget(collapsible(sets: const []));
      await tester.tap(find.byTooltip('Collapse exercise'));
      await tester.pump();
      expect(find.text('No sets yet'), findsOneWidget);

      await tester.pumpWidget(collapsible(sets: const [ActivitySet(uid: 1, completed: false)]));
      expect(find.text('0 of 1 set done'), findsOneWidget);
    });

    testWidgets('is off by default: no chevron, title does nothing', (tester) async {
      await tester.pumpWidget(collapsible(enabled: false));

      expect(find.byTooltip('Collapse exercise'), findsNothing);
      await tester.tap(find.text('Bench Press'));
      await tester.pump();
      expect(find.byType(ActivitySetRow), findsNWidgets(3));
    });
  });
}
