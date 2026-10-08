import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/design_tokens.dart';
import '../../models/planned_workout.dart';
import 'planned_workout_tile.dart';
import 'start_planned_workout.dart';

/// The next few planned workouts, at the top of the Home screen, with a
/// shortcut to schedule another. A workout due today can be started from here.
class UpcomingWorkoutsCard extends ConsumerWidget {
  const UpcomingWorkoutsCard({super.key, required this.plans, this.limit = 3, this.now});

  final List<PlannedWorkout> plans;
  final int limit;

  /// For tests; the real clock otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = now ?? DateTime.now();
    final upcoming = upcomingPlannedWorkouts(plans, clock);
    final dueToday = todaysPlannedWorkouts(plans, clock).map((p) => p.id).toSet();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_rounded, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Upcoming', style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: () => context.go('/activities/plan/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Schedule'),
                ),
              ],
            ),
            if (upcoming.isEmpty)
              Text(
                'Nothing planned. Schedule a routine to get a reminder when it is time.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            else
              for (final plan in upcoming.take(limit))
                PlannedWorkoutTile(
                  plan: plan,
                  onStart: dueToday.contains(plan.id)
                      ? () async {
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
          ],
        ),
      ),
    );
  }
}
