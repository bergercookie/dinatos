import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dinatos/features/activities/widgets/activity_exercise_card.dart';

void main() {
  testWidgets('stopping writes elapsed seconds; replay resumes; override wins', (tester) async {
    int? seconds;
    var clock = DateTime(2026);
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SetStopwatch(
                seconds: seconds,
                onStopped: (v) => seconds = v,
                now: () => clock,
              );
            },
          ),
        ),
      ),
    );
    final button = find.byKey(const ValueKey('set-timer'));
    await tester.tap(button);
    clock = clock.add(const Duration(seconds: 3));
    await tester.tap(button);
    rebuild(() {});
    await tester.pump();
    expect(seconds, 3);

    await tester.tap(button);
    clock = clock.add(const Duration(seconds: 2));
    await tester.tap(button);
    rebuild(() {});
    await tester.pump();
    expect(seconds, 5);

    rebuild(() => seconds = 30);
    await tester.pump();
    await tester.tap(button);
    clock = clock.add(const Duration(seconds: 1));
    await tester.tap(button);
    expect(seconds, 31);
  });
}
