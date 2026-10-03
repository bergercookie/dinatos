import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/widgets/bar_charts.dart';
import '../../models/activity.dart';
import 'training_stats.dart';

/// The compact "Your training" card on the Home screen: three headline
/// numbers, a small weekly chart, and a button to the full stats page. Kept
/// to the activities the screen already loaded -- no catalog needed.
class StatsSummaryCard extends StatelessWidget {
  const StatsSummaryCard({super.key, required this.activities, required this.onOpenStats});

  final List<Activity> activities;
  final VoidCallback onOpenStats;

  @override
  Widget build(BuildContext context) {
    final stats = TrainingStats.compute(activities, range: StatsRange.month);
    final average = stats.averageDuration;
    final weekly = stats.weeklyCounts;
    final weekStarts = stats.weekStarts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 30 days', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.fitness_center,
                    value: '${stats.workouts}',
                    label: stats.workouts == 1 ? 'workout' : 'workouts',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.event_repeat,
                    value: stats.workoutsPerWeek.toStringAsFixed(1),
                    label: 'per week',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.timer_outlined,
                    value: average == null ? '–' : formatDuration(average),
                    label: 'avg workout',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            VerticalBarChart(
              height: 56,
              values: weekly,
              labels: [for (var i = 0; i < weekStarts.length; i++) ''],
              highlightIndex: weekly.length - 1,
              semanticsLabel: 'Workouts per week, last ${weekly.length} weeks',
            ),
            Text(
              'Workouts per week, last ${weekly.length} weeks',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenStats,
                icon: const Icon(Icons.insights),
                label: const Text('All stats'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
