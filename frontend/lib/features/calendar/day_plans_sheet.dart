import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_exception.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../models/activity.dart';
import '../../models/planned_workout.dart';
import 'planned_workout_tile.dart';
import 'start_planned_workout.dart';

/// What a tap on a calendar day opens. Today and later: that day's planned
/// workouts (tap one to edit it, or start it when it is due today) and a way
/// to plan another. A day already behind us: the activities actually logged
/// on it, since what was planned no longer matters.
Future<void> showDayPlansSheet(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
  List<PlannedWorkout> all, {
  List<Activity> activities = const [],
}) {
  final plans = all.where((p) => DateUtils.isSameDay(p.scheduledAt.toLocal(), day)).toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  final today = DateUtils.dateOnly(DateTime.now());
  final isPast = day.isBefore(today);
  final isToday = DateUtils.isSameDay(day, today);
  final done = activities.where((a) => DateUtils.isSameDay(a.startedAt.toLocal(), day)).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

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
            if (isPast ? done.isEmpty : plans.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  isPast ? 'No activities were completed on this day.' : 'Nothing planned yet.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            if (isPast)
              for (final activity in done)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppListCard(
                    leading: const AppIconAvatar(icon: Icons.history_rounded),
                    title: activity.title,
                    subtitle: Text(
                      '${DateFormat.Hm().format(activity.startedAt.toLocal())} · '
                      '${activity.exercises.length} exercise'
                      '${activity.exercises.length == 1 ? '' : 's'}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.go('/activities/${activity.id}');
                    },
                  ),
                )
            else
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
