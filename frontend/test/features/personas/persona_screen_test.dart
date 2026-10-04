import 'package:dinatos_frontend/features/activities/activities_providers.dart';
import 'package:dinatos_frontend/features/measurements/measurements_providers.dart';
import 'package:dinatos_frontend/features/personas/persona_screen.dart';
import 'package:dinatos_frontend/features/profile/profile_providers.dart';
import 'package:dinatos_frontend/features/stats/stats_screen.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/exercise.dart';
import 'package:dinatos_frontend/models/measurement.dart';
import 'package:dinatos_frontend/models/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  List<Activity> activities = const [],
  List<BodyMeasurement> measurements = const [],
  double? heightCm,
}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activityListProvider.overrideWith((ref) async => activities),
        measurementListProvider.overrideWith((ref) async => measurements),
        profileProvider.overrideWith(
          (ref) async => Profile(heightCm: heightCm, unitSystem: UnitSystem.metric),
        ),
        fullCatalogProvider.overrideWith(
          (ref) async => const [Exercise(id: 1, name: 'Squat (Barbell)')],
        ),
      ],
      child: const MaterialApp(home: PersonaScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no data it asks for measurements and training', (tester) async {
    await _pump(tester);

    expect(find.text('Athlete match'), findsOneWidget);
    expect(find.textContaining('Not enough measurements'), findsOneWidget);
    expect(find.textContaining('Log more training'), findsOneWidget);
    expect(find.textContaining('Add height (in your profile)'), findsOneWidget);
    // The persona picker is still there to browse.
    expect(find.widgetWithText(ChoiceChip, 'Sprinter'), findsOneWidget);
  });

  testWidgets('shows body and training matches and lets you pick a persona', (tester) async {
    await _pump(
      tester,
      heightCm: 175,
      measurements: [
        BodyMeasurement(
          measuredAt: DateTime(2026, 9, 1),
          weightKg: 62,
          fatPercent: 7,
          waistCm: 72,
          shoulderCm: 94,
          leftThighCm: 49,
          leftBicepCm: 28,
        ),
      ],
      activities: [
        Activity(
          title: 'Legs',
          startedAt: DateTime.now().subtract(const Duration(days: 2)),
          exercises: [
            ActivityExercise(
              exerciseId: 1,
              sets: [for (var i = 0; i < 12; i++) const ActivitySet(weightKg: 100, reps: 10)],
            ),
          ],
        ),
      ],
    );

    expect(find.textContaining('Your body looks most like a'), findsOneWidget);
    expect(find.text('Distance runner'), findsWidgets);
    expect(find.textContaining('Your training looks most like a'), findsOneWidget);
    expect(find.text('Bodybuilder'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Gymnast'));
    await tester.pumpAndSettle();
    expect(find.text('Gymnast'), findsWidgets);
    expect(find.textContaining('To train more like a gymnast'), findsOneWidget);
    expect(find.text('Shoulder-to-waist'), findsOneWidget);
  });

  testWidgets('the radar chart describes itself to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.bySemanticsLabel(RegExp(r'^Match with each athlete')), findsOneWidget);
    handle.dispose();
  });
}
