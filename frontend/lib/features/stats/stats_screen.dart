import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/bar_charts.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/activity.dart';
import '../../models/exercise.dart';
import '../activities/activities_providers.dart';
import '../exercises/exercises_repository.dart';
import 'training_stats.dart';

const _topN = 5;
const _topMuscles = 10;

/// The full stats page behind the Home screen's "All stats" button:
/// frequency, duration, volume, muscle split, favourite exercises, best
/// lifts -- all derived on the device from the person's logged activities.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsRange _range = StatsRange.quarter;

  @override
  Widget build(BuildContext context) {
    final activities = ref.watch(activityListProvider);
    // Not `exerciseListProvider`: that one is filtered by the exercise
    // search box, which would silently change names and muscles here.
    final catalog = ref.watch(_fullCatalogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        leading: BackButton(onPressed: () => context.go('/activities')),
      ),
      body: ResponsiveBody(
        child: AsyncValueView<List<Activity>>(
          value: activities,
          onRetry: () => ref.invalidate(activityListProvider),
          builder: (context, data) {
            if (data.isEmpty) {
              return const EmptyState(
                icon: Icons.insights,
                title: 'Nothing to chart yet',
                message: 'Log a few workouts and your stats will show up here.',
              );
            }
            // Names and muscles are a nicety: show the rest while the
            // catalog loads, or if it fails.
            final stats = TrainingStats.compute(
              data,
              catalog: catalog.valueOrNull ?? const <Exercise>[],
              range: _range,
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                SegmentedButton<StatsRange>(
                  showSelectedIcon: false,
                  segments: [
                    for (final r in StatsRange.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                if (stats.workouts == 0)
                  const _SectionCard(
                    title: 'No workouts in this period',
                    child: Text('Pick a longer range to see more.'),
                  )
                else ...[
                  _Overview(stats: stats),
                  _SectionCard(
                    title: 'Workouts per week',
                    subtitle: 'Last $statsWeeklyChartWeeks weeks, oldest to newest',
                    child: VerticalBarChart(
                      values: stats.weeklyCounts,
                      labels: [
                        for (var i = 0; i < stats.weekStarts.length; i++)
                          i % 3 == 0 || i == stats.weekStarts.length - 1
                              ? DateFormat.Md().format(stats.weekStarts[i])
                              : '',
                      ],
                      highlightIndex: stats.weeklyCounts.length - 1,
                      semanticsLabel:
                          'Workouts per week over the last $statsWeeklyChartWeeks weeks',
                    ),
                  ),
                  _SectionCard(
                    title: 'Favourite days',
                    subtitle: 'Workouts by day of the week',
                    child: VerticalBarChart(
                      values: stats.weekdayCounts,
                      labels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                      highlightIndex: _busiestDay(stats.weekdayCounts),
                      semanticsLabel: 'Workouts by day of the week',
                    ),
                  ),
                  _SectionCard(
                    title: 'Muscle distribution',
                    subtitle: 'Working sets per muscle (secondary muscles count half)',
                    child: _MuscleSection(stats: stats, catalog: catalog),
                  ),
                  _SectionCard(
                    title: 'Go-to exercises',
                    subtitle: 'Most often performed',
                    child: stats.topExercises.isEmpty
                        ? const Text('No exercises logged yet.')
                        : HorizontalBarList(
                            rows: [
                              for (final e in stats.topExercises.take(_topN))
                                BarRow(
                                  label: e.name,
                                  value: e.sessions.toDouble(),
                                  valueLabel: '${e.sessions}×',
                                  caption: '${e.sets} sets in total',
                                ),
                            ],
                          ),
                  ),
                  _SectionCard(
                    title: 'Strongest lifts',
                    subtitle: 'Best set by estimated one-rep max (Epley)',
                    child: _LiftsSection(stats: stats, catalog: catalog),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The whole catalog, unfiltered; only this screen uses it.
final _fullCatalogProvider = FutureProvider.autoDispose<List<Exercise>>(
  (ref) => ref.watch(exercisesRepositoryProvider).list(),
);

int? _busiestDay(List<int> counts) {
  final max = counts.reduce((a, b) => a > b ? a : b);
  return max == 0 ? null : counts.indexOf(max);
}

class _Overview extends StatelessWidget {
  const _Overview({required this.stats});

  final TrainingStats stats;

  @override
  Widget build(BuildContext context) {
    final average = stats.averageDuration;
    final tiles = [
      StatTile(
        icon: Icons.fitness_center,
        value: '${stats.workouts}',
        label: stats.workouts == 1 ? 'workout' : 'workouts',
      ),
      StatTile(
        icon: Icons.event_repeat,
        value: stats.workoutsPerWeek.toStringAsFixed(1),
        label: 'workouts / week',
      ),
      StatTile(
        icon: Icons.timer_outlined,
        value: average == null ? '–' : formatDuration(average),
        label: 'average workout',
      ),
      StatTile(
        icon: Icons.hourglass_bottom,
        value: stats.timedWorkouts == 0 ? '–' : formatDuration(stats.longestDuration),
        label: 'longest workout',
      ),
      StatTile(
        icon: Icons.schedule,
        value: stats.timedWorkouts == 0 ? '–' : formatDuration(stats.totalDuration),
        label: 'total time',
      ),
      StatTile(icon: Icons.layers, value: '${stats.totalSets}', label: 'sets'),
      StatTile(icon: Icons.scale, value: formatWeight(stats.totalVolumeKg), label: 'volume lifted'),
      StatTile(
        icon: Icons.local_fire_department,
        value: '${stats.longestDayStreak}',
        label: stats.longestDayStreak == 1 ? 'day best streak' : 'days best streak',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 480 ? 4 : 2;
          final width = (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleMedium),
            if (subtitle != null)
              Text(
                subtitle!,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _MuscleSection extends StatelessWidget {
  const _MuscleSection({required this.stats, required this.catalog});

  final TrainingStats stats;
  final AsyncValue<List<Exercise>> catalog;

  @override
  Widget build(BuildContext context) {
    if (catalog.isLoading) return const Center(child: CircularProgressIndicator());
    final sorted = stats.muscleSets.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isEmpty) return const Text('No muscle data for the exercises logged.');
    final total = sorted.fold<double>(0, (sum, e) => sum + e.value);
    return HorizontalBarList(
      rows: [
        for (final e in sorted.take(_topMuscles))
          BarRow(
            label: e.key.label,
            value: e.value,
            valueLabel: '${(100 * e.value / total).round()}% · ${_sets(e.value)}',
          ),
      ],
    );
  }

  String _sets(double sets) {
    final text = sets == sets.roundToDouble() ? sets.round().toString() : sets.toStringAsFixed(1);
    return '$text sets';
  }
}

class _LiftsSection extends StatelessWidget {
  const _LiftsSection({required this.stats, required this.catalog});

  final TrainingStats stats;
  final AsyncValue<List<Exercise>> catalog;

  @override
  Widget build(BuildContext context) {
    if (catalog.isLoading) return const Center(child: CircularProgressIndicator());
    if (stats.topLifts.isEmpty) return const Text('Log some weighted sets to see your best lifts.');
    return HorizontalBarList(
      rows: [
        for (final l in stats.topLifts.take(_topN))
          BarRow(
            label: l.name,
            value: l.estimatedOneRepMaxKg,
            valueLabel: '≈ ${formatWeight(l.estimatedOneRepMaxKg)}',
            caption:
                'Best set: ${l.weightKg.toStringAsFixed(l.weightKg % 1 == 0 ? 0 : 1)} kg × ${l.reps}',
          ),
      ],
    );
  }
}
