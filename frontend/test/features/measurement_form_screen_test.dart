import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/measurements/measurement_form_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// The form lists 16 measurement fields in a [ListView], taller than the
/// default 800x600 test surface -- grown here so every field (and the
/// Save/Create button after them) is actually built, not just scrolled past.
void _growTestSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
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
}
