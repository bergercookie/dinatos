import 'package:dinatos_frontend/features/activities/widgets/training_calendar_card.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/planned_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

Activity _activityOn(DateTime date) => Activity(title: 't', startedAt: date, exercises: const []);

Future<void> _pump(WidgetTester tester, List<Activity> activities) {
  // In the real app this card is the first item of a scrolling ListView (see
  // ActivityListScreen), never given a bounded height directly -- match that
  // here instead of cramming a fixed-size month grid into the test's default
  // surface size.
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: TrainingCalendarCard(activities: activities)),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a "no streak" message with no training history', (tester) async {
    await _pump(tester, const []);

    expect(find.textContaining('No active streak'), findsOneWidget);
    expect(find.text(DateFormat.yMMMM().format(DateTime.now())), findsOneWidget);
  });

  testWidgets('reports the current day and week streak from today backward', (tester) async {
    final today = DateTime.now();
    await _pump(tester, [_activityOn(today), _activityOn(today.subtract(const Duration(days: 1)))]);

    expect(find.textContaining('2 days in a row'), findsOneWidget);
    expect(find.textContaining('week'), findsOneWidget);
  });

  testWidgets('previous/next month navigation updates the header, forward into the future too', (
    tester,
  ) async {
    await _pump(tester, const []);
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);

    expect(find.text(DateFormat.yMMMM().format(now)), findsOneWidget);
    final nextMonth = DateTime(now.year, now.month + 1);
    // Future months can be browsed, to see what is planned there.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pump();
    expect(find.text(DateFormat.yMMMM().format(nextMonth)), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
    await tester.pump();
    expect(find.text(DateFormat.yMMMM().format(lastMonth)), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pump();
    expect(find.text(DateFormat.yMMMM().format(now)), findsOneWidget);
  });

  testWidgets('marks days with a planned workout and reports taps on a day', (tester) async {
    final now = DateTime.now();
    final planned = DateTime(now.year, now.month, 15, 18);
    DateTime? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrainingCalendarCard(
              activities: const [],
              plannedWorkouts: [PlannedWorkout(id: 1, title: 'Push', scheduledAt: planned)],
              onDayTap: (day) => tapped = day,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('planned-dot')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('workout planned')));
    expect(tapped, DateTime(now.year, now.month, 15));
  });

  testWidgets('a completed plan is not marked', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrainingCalendarCard(
              activities: const [],
              plannedWorkouts: [
                PlannedWorkout(
                  id: 1,
                  title: 'Push',
                  scheduledAt: DateTime(now.year, now.month, 15, 18),
                  completedActivityId: 9,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('planned-dot')), findsNothing);
  });
}
