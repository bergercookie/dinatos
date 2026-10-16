import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dinatos_frontend/features/activities/widgets/activity_exercise_card.dart';

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

  testWidgets('ticking the set done while running stops the timer', (tester) async {
    int? seconds;
    var completed = false;
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
                completed: completed,
                onStopped: (v) => seconds = v,
                now: () => clock,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('set-timer')));
    clock = clock.add(const Duration(seconds: 4));
    rebuild(() => completed = true);
    await tester.pump();
    await tester.pump();
    expect(seconds, 4);
    expect(find.byKey(const ValueKey('set-timer-elapsed')), findsNothing);
  });
}
