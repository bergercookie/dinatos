import 'dart:async';

import 'package:dinatos_frontend/features/routines/routine_form_screen.dart';
import 'package:dinatos_frontend/features/routines/routine_shortcuts.dart';
import 'package:dinatos_frontend/features/routines/routines_providers.dart';
import 'package:dinatos_frontend/models/routine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Service implements RoutineShortcutService {
  _Service({this.supported = true, this.answer = true, this.error});

  final bool supported;
  final bool answer;
  final ShortcutException? error;
  final pinned = <({int routineId, String name})>[];

  @override
  bool get isSupported => supported;

  @override
  Future<bool> pin({required int routineId, required String name}) async {
    pinned.add((routineId: routineId, name: name));
    if (error != null) throw error!;
    return answer;
  }

  @override
  Future<int?> initialRoutineId() async => null;

  @override
  Stream<int> get routineLaunches => const Stream.empty();
}

const _routine = Routine(id: 7, name: 'Upper', exercises: []);

Future<void> _pump(WidgetTester tester, _Service service) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routineShortcutServiceProvider.overrideWithValue(service),
        routineProvider(7).overrideWith((ref) async => _routine),
      ],
      child: const MaterialApp(home: RoutineFormScreen(routineId: 7)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('is offered on the routine where shortcuts are supported', (tester) async {
    await _pump(tester, _Service());
    expect(find.byTooltip('Add to home screen'), findsOneWidget);
  });

  testWidgets('is hidden where shortcuts are not supported (web, desktop, iOS)', (tester) async {
    await _pump(tester, _Service(supported: false));
    expect(find.byTooltip('Add to home screen'), findsNothing);
    // The rest of the screen is unaffected.
    expect(find.byTooltip('Delete routine'), findsOneWidget);
  });

  testWidgets('is not offered while creating a routine that has no id yet', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [routineShortcutServiceProvider.overrideWithValue(_Service())],
        child: const MaterialApp(home: RoutineFormScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add to home screen'), findsNothing);
  });

  testWidgets('pins the saved routine by id and name, and says to confirm', (tester) async {
    final service = _Service();
    await _pump(tester, service);

    await tester.tap(find.byTooltip('Add to home screen'));
    await tester.pumpAndSettle();

    expect(service.pinned, [(routineId: 7, name: 'Upper')]);
    expect(find.textContaining('Confirm in the Android prompt'), findsOneWidget);
    expect(find.textContaining('"Upper"'), findsOneWidget);
  });

  testWidgets('says so when the launcher cannot add shortcuts', (tester) async {
    await _pump(tester, _Service(answer: false));

    await tester.tap(find.byTooltip('Add to home screen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('launcher cannot add'), findsOneWidget);
  });

  testWidgets('shows the error when the request fails', (tester) async {
    await _pump(tester, _Service(error: const ShortcutException('no activity')));

    await tester.tap(find.byTooltip('Add to home screen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not add the shortcut: no activity'), findsOneWidget);
  });
}
