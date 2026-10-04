import 'dart:async';

import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/measurements/measurement_form_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

Response<Map<String, dynamic>> _measurementResponse(int id) => Response(
  requestOptions: RequestOptions(path: '/measurements/$id'),
  statusCode: 200,
  data: {
    'id': id,
    'measured_at': '2026-01-01T00:00:00Z',
    'weight_kg': 70.5,
    'fat_percent': 15.0,
    'neck_cm': null,
    'shoulder_cm': null,
    'chest_cm': null,
    'left_bicep_cm': null,
    'right_bicep_cm': null,
    'left_forearm_cm': null,
    'right_forearm_cm': null,
    'abdomen_cm': null,
    'waist_cm': null,
    'hips_cm': null,
    'left_thigh_cm': null,
    'right_thigh_cm': null,
    'left_calf_cm': null,
    'right_calf_cm': null,
  },
);

/// The form lists 33 measurement fields in a [ListView], taller than the
/// default 800x600 test surface -- grown here so every field (and the
/// Save/Create button after them) is actually built, not just scrolled past.
void _growTestSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 7000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('creating a new measurement shows no delete action', (tester) async {
    _growTestSurface(tester);
    final dio = MockDio();
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MeasurementFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New measurement'), findsOneWidget);
    expect(find.byTooltip('Delete measurement'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
  });

  testWidgets('editing an existing measurement loads its values and offers delete', (tester) async {
    _growTestSurface(tester);
    final dio = MockDio();
    when(() => dio.get<Map<String, dynamic>>('/measurements/1'))
        .thenAnswer((_) async => _measurementResponse(1));
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MeasurementFormScreen(measurementId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit measurement'), findsOneWidget);
    expect(find.byTooltip('Delete measurement'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    final weightField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Weight (kg)').first,
    );
    expect(weightField.controller?.text, '70.5');
  });

  testWidgets('groups the fields into body composition, segmental and tape sections', (
    tester,
  ) async {
    _growTestSurface(tester);
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(MockDio())]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MeasurementFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final title in ['Body composition', 'Segmental analysis', 'Tape measurements']) {
      expect(find.text(title), findsOneWidget);
    }
    for (final label in [
      'Muscle mass (kg)',
      'Bone mass (kg)',
      'BMI',
      'DCI (kcal)',
      'Metabolic age (years)',
      'Water (%)',
      'Visceral fat (rating)',
      'Right arm fat (%)',
      'Right arm muscle (kg)',
      'Left arm muscle (kg)',
      'Right leg fat (%)',
      'Left leg muscle (kg)',
      'Trunk fat (%)',
      'Trunk muscle (kg)',
      'Waist (cm)',
    ]) {
      expect(find.widgetWithText(TextField, label), findsOneWidget, reason: label);
    }
    // Whole-number fields don't offer a decimal point.
    final age = tester.widget<TextField>(find.widgetWithText(TextField, 'Metabolic age (years)'));
    expect(age.keyboardType, const TextInputType.numberWithOptions(decimal: false));
    final bmi = tester.widget<TextField>(find.widgetWithText(TextField, 'BMI'));
    expect(bmi.keyboardType, const TextInputType.numberWithOptions(decimal: true));
  });

  testWidgets('saves smart-scale values, whole numbers as integers', (tester) async {
    _growTestSurface(tester);
    final dio = MockDio();
    Map<String, dynamic>? sent;
    when(() => dio.post<Map<String, dynamic>>('/measurements', data: any(named: 'data')))
        .thenAnswer((invocation) async {
          sent = invocation.namedArguments[#data] as Map<String, dynamic>;
          return Response(
            requestOptions: RequestOptions(path: '/measurements'),
            statusCode: 201,
            data: {'id': 7, ...sent!},
          );
        });
    when(() => dio.get<List<dynamic>>('/measurements')).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/measurements'),
        statusCode: 200,
        data: <dynamic>[],
      ),
    );
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    // `pop` after saving needs a route to pop back to.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(path: '/new', builder: (context, state) => const MeasurementFormScreen()),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    unawaited(router.push('/new'));
    await tester.pumpAndSettle();

    Future<void> enter(String label, String text) =>
        tester.enterText(find.widgetWithText(TextField, label), text);
    await enter('Weight (kg)', '70.5');
    await enter('Muscle mass (kg)', '55.1');
    await enter('Metabolic age (years)', '27');
    await enter('DCI (kcal)', '2410');
    await enter('Right arm muscle (kg)', '3.2');
    await enter('Trunk fat (%)', '16.3');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!['weight_kg'], 70.5);
    expect(sent!['muscle_mass_kg'], 55.1);
    expect(sent!['metabolic_age'], 27);
    expect(sent!['dci_kcal'], 2410);
    expect(sent!['right_arm_muscle_kg'], 3.2);
    expect(sent!['trunk_fat_percent'], 16.3);
    // What was left blank stays null rather than becoming zero.
    expect(sent!['bone_mass_kg'], isNull);
    expect(sent!['waist_cm'], isNull);
    expect(find.text('home'), findsOneWidget);
  });
}
