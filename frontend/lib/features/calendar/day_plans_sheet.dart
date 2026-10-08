import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_exception.dart';
import '../../core/design_tokens.dart';
import '../../models/planned_workout.dart';
import 'planned_workout_tile.dart';
import 'start_planned_workout.dart';

/// What a tap on a calendar day opens: that day's planned workouts (tap one
/// to edit it, or start it when it is due today) and a way to plan another
/// for that day -- unless the day is already behind us.
Future<void> showDayPlansSheet(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
  List<PlannedWorkout> all,
) {
  final plans = all.where((p) => DateUtils.isSameDay(p.scheduledAt.toLocal(), day)).toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  final today = DateUtils.dateOnly(DateTime.now());
  final isPast = day.isBefore(today);
  final isToday = DateUtils.isSameDay(day, today);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(DateFormat.yMMMEd().format(day), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (plans.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  isPast ? 'Nothing was planned for this day.' : 'Nothing planned yet.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            for (final plan in plans)
              PlannedWorkoutTile(
                plan: plan,
                showDate: false,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go('/activities/plan/${plan.id}');
                },
                onStart: isToday && !plan.isCompleted
                    ? () async {
                        Navigator.of(sheetContext).pop();
                        try {
                          await startPlannedWorkout(context, ref, plan);
                        } on ApiException catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not start it: ${error.message}')),
                            );
                          }
                        }
                      }
                    : null,
              ),
            if (!isPast) ...[
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.go('/activities/plan/new?date=${DateFormat('yyyy-MM-dd').format(day)}');
                },
                icon: const Icon(Icons.add),
                label: const Text('Schedule workout'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
