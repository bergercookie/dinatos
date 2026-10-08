import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_tokens.dart';
import '../../../models/activity.dart';
import '../../../models/planned_workout.dart';
import 'training_streak.dart';

/// A month calendar marking which days the person actually trained, plus
/// their current day/week streak -- shown at the top of the Home screen's
/// activity list. Built from whatever [activities] the caller already has
/// loaded (the same list the screen below renders), not a separate fetch.
///
/// Days with a workout still planned ([plannedWorkouts]) carry a dot, and a
/// tap on any day reports it through [onDayTap] (the Home screen opens that
/// day's plans). Months can be browsed into the future, to see what is planned.
class TrainingCalendarCard extends StatefulWidget {
  const TrainingCalendarCard({
    super.key,
    required this.activities,
    this.plannedWorkouts = const [],
    this.onDayTap,
  });

  final List<Activity> activities;
  final List<PlannedWorkout> plannedWorkouts;
  final void Function(DateTime day)? onDayTap;

  @override
  State<TrainingCalendarCard> createState() => _TrainingCalendarCardState();
}

class _TrainingCalendarCardState extends State<TrainingCalendarCard> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _previousMonth() => setState(() => _month = DateTime(_month.year, _month.month - 1));

  void _nextMonth() => setState(() => _month = DateTime(_month.year, _month.month + 1));

  @override
  Widget build(BuildContext context) {
    final trainingDates = trainingDatesFrom(widget.activities);
    final dayStreak = currentDayStreak(trainingDates);
    final weekStreak = currentWeekStreak(trainingDates);
    final today = dateOnly(DateTime.now());
    final planned = plannedDates(widget.plannedWorkouts);

    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = _month.weekday - 1;
    final cells = <DateTime?>[
      for (var i = 0; i < leadingBlanks; i++) null,
      for (var day = 1; day <= daysInMonth; day++) DateTime(_month.year, _month.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StreakSummary(dayStreak: dayStreak, weekStreak: weekStreak),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _previousMonth,
                ),
                Text(
                  DateFormat.yMMMM().format(_month),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextMonth,
                ),
              ],
            ),
            Row(
              children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map(
                    (label) => Expanded(
                      child: Center(
                        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  )
                  .toList(),
            ),
            for (var row = 0; row < cells.length; row += 7)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: cells
                      .skip(row)
                      .take(7)
                      .map(
                        (date) => Expanded(
                          child: _DayCell(
                            date: date,
                            trained: date != null && trainingDates.contains(date),
                            isToday: date != null && date == today,
                            planned: date != null && planned.contains(date),
                            onTap: date == null || widget.onDayTap == null
                                ? null
                                : () => widget.onDayTap!(date),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StreakSummary extends StatelessWidget {
  const _StreakSummary({required this.dayStreak, required this.weekStreak});

  final int dayStreak;
  final int weekStreak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (dayStreak == 0 && weekStreak == 0) {
      return Text(
        'No active streak yet — log a workout to start one.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        if (dayStreak > 0)
          _StreakChip(
            icon: Icons.local_fire_department,
            text: '$dayStreak day${dayStreak == 1 ? '' : 's'} in a row',
          ),
        if (weekStreak > 0)
          _StreakChip(
            icon: Icons.calendar_month,
            text: '$weekStreak week${weekStreak == 1 ? '' : 's'} in a row',
          ),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: scheme.tertiary),
        const SizedBox(width: AppSpacing.xs),
        Text(text, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.trained,
    required this.isToday,
    required this.planned,
    this.onTap,
  });

  final DateTime? date;
  final bool trained;
  final bool isToday;
  final bool planned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    if (date == null) return const SizedBox(height: 32);
    final scheme = Theme.of(context).colorScheme;
    final label = [
      DateFormat.MMMMd().format(date),
      if (trained) 'trained',
      if (planned) 'workout planned',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        label: label,
        button: onTap != null,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: trained ? scheme.primary : null,
                border: isToday && !trained ? Border.all(color: scheme.primary, width: 1.5) : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: trained
                          ? scheme.onPrimary
                          : (isToday ? scheme.primary : scheme.onSurface),
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  if (planned)
                    Positioned(
                      bottom: 3,
                      child: Container(
                        key: const ValueKey('planned-dot'),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: trained ? scheme.onPrimary : scheme.tertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
