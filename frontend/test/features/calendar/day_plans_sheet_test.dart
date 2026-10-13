import 'package:dinatos_frontend/features/calendar/day_plans_sheet.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester, DateTime day, List<Activity> activities) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showDayPlansSheet(context, ref, day, const [], activities: activities),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  final today = DateUtils.dateOnly(DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));

  testWidgets('a past day lists the activities completed on it', (tester) async {
    await _open(tester, yesterday, [
      Activity(
        title: 'Leg day',
        startedAt: yesterday.add(const Duration(hours: 9)),
        exercises: const [],
      ),
      Activity(title: 'Other day', startedAt: today, exercises: const []),
    ]);

    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Other day'), findsNothing);
    expect(find.text('Schedule workout'), findsNothing);
  });

  testWidgets('a past day with nothing logged says so', (tester) async {
    await _open(tester, yesterday, const []);

    expect(find.text('No activities were completed on this day.'), findsOneWidget);
  });

  testWidgets('today shows plans, not completed activities', (tester) async {
    await _open(tester, today, [Activity(title: 'Leg day', startedAt: today, exercises: const [])]);

    expect(find.text('Leg day'), findsNothing);
    expect(find.text('Nothing planned yet.'), findsOneWidget);
    expect(find.text('Schedule workout'), findsOneWidget);
  });
}
