import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/features/exercises/exercise_form_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

Response<Map<String, dynamic>> _exerciseResponse(int id, String name, {required bool isCustom}) =>
    Response(
      requestOptions: RequestOptions(path: '/exercises/$id'),
      statusCode: 200,
      data: {
        'id': id,
        'name': name,
        'tracks_weight': true,
        'tracks_reps': true,
        'tracks_distance': false,
        'tracks_duration': false,
        'is_custom': isCustom,
      },
    );

void main() {
  testWidgets('a built-in exercise renders read-only, with no delete action', (tester) async {
    // Tall enough that the whole form (now with the muscle-tag fields too)
    // fits without scrolling -- otherwise the ListView's sliver only builds
    // what's within its viewport/cache extent, and a widget further down
    // (like the Save button below) simply isn't in the tree to find yet.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dio = MockDio();
    when(() => dio.get<Map<String, dynamic>>('/exercises/1'))
        .thenAnswer((_) async => _exerciseResponse(1, 'Squat (Barbell)', isCustom: false));
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseFormScreen(exerciseId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        "This is a built-in exercise and cannot be edited or deleted. "
        "Add a custom exercise instead if you need something different.",
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Delete exercise'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);

    final nameField = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(nameField.enabled, isFalse);
    for (final checkbox in tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile))) {
      expect(checkbox.onChanged, isNull);
    }
  });

  testWidgets('a custom exercise stays editable, with a delete action', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dio = MockDio();
    when(() => dio.get<Map<String, dynamic>>('/exercises/2'))
        .thenAnswer((_) async => _exerciseResponse(2, 'My Custom Move', isCustom: true));
    final container = ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExerciseFormScreen(exerciseId: 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Delete exercise'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    final nameField = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(nameField.enabled, isTrue);
    for (final checkbox in tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile))) {
      expect(checkbox.onChanged, isNotNull);
    }
  });
}
