import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/app_list_card.dart';
import '../../models/planned_workout.dart';

/// One planned workout as a list row: what, when, and a play button to start
/// it. Tapping the row edits the plan.
class PlannedWorkoutTile extends StatelessWidget {
  const PlannedWorkoutTile({
    super.key,
    required this.plan,
    this.showDate = true,
    this.onStart,
    this.onTap,
  });

  final PlannedWorkout plan;
  final bool showDate;

  /// Shown as a play button when set (only sensible for a workout that is due today).
  final VoidCallback? onStart;

  /// Overrides opening the plan's edit screen (a sheet closes itself first).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final when = showDate
        ? DateFormat.MMMEd().add_Hm().format(plan.scheduledAt)
        : DateFormat.Hm().format(plan.scheduledAt);
    return AppListCard(
      leading: const AppIconAvatar(icon: Icons.event_rounded),
      title: plan.title,
      subtitle: Text('$when · ${plan.durationMinutes} min'),
      trailing: onStart == null
          ? const Icon(Icons.chevron_right_rounded)
          : IconButton.filledTonal(
              tooltip: 'Start ${plan.title}',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: onStart,
            ),
      onTap: onTap ?? () => context.go('/activities/plan/${plan.id}'),
    );
  }
}
