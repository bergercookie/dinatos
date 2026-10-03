import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/line_chart.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/exercise_history.dart';
import '../exercises/exercises_providers.dart';
import 'progression.dart';

/// What the chart plots for each session.
enum ProgressMetric {
  oneRepMax('Est. 1RM', 'Estimated one-rep max'),
  topWeight('Top set', 'Heaviest set'),
  volume('Volume', 'Total volume'),
  bestReps('Best reps', 'Most reps in a set');

  const ProgressMetric(this.label, this.title);

  final String label;
  final String title;

  double? valueOf(SessionStats stats) => switch (this) {
    oneRepMax => stats.bestOneRepMaxKg,
    topWeight => stats.topWeightKg,
    volume => stats.volumeKg > 0 ? stats.volumeKg : null,
    bestReps => stats.bestReps?.toDouble(),
  };

  String format(double value) => switch (this) {
    bestReps => '${value.round()} reps',
    _ => '${formatKg(double.parse(value.toStringAsFixed(1)))} kg',
  };
}

/// One exercise's history over time: a chart of estimated 1RM, heaviest set,
/// volume or best reps per session, a suggestion for the next session, a
/// notice when progress has stalled, and the recent sessions themselves. All
/// of it is computed from `GET /exercises/{id}/history` -- see `progression.dart`.
class ExerciseProgressScreen extends ConsumerStatefulWidget {
  const ExerciseProgressScreen({super.key, required this.exerciseId});

  final int exerciseId;

  @override
  ConsumerState<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _ExerciseProgressScreenState extends ConsumerState<ExerciseProgressScreen> {
  ProgressMetric? _chosen;

  @override
  Widget build(BuildContext context) {
    final exercise = ref.watch(exerciseProvider(widget.exerciseId));
    final history = ref.watch(exerciseHistoryProvider(widget.exerciseId));
    return Scaffold(
      appBar: AppBar(title: Text(exercise.valueOrNull?.name ?? 'Progress')),
      body: ResponsiveBody(
        child: AsyncValueView(
          value: history,
          onRetry: () => ref.invalidate(exerciseHistoryProvider(widget.exerciseId)),
          builder: (context, entries) {
            final timeline = sessionTimeline(entries);
            if (timeline.isEmpty) {
              return const EmptyState(
                icon: Icons.show_chart_rounded,
                title: 'No sessions yet',
                message: 'Log this exercise in a workout and its progress will show up here.',
              );
            }
            return _buildContent(context, entries, timeline);
          },
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<ExerciseHistoryEntry> entries,
    List<SessionStats> timeline,
  ) {
    final available = [
      for (final metric in ProgressMetric.values)
        if (timeline.any((s) => metric.valueOf(s) != null)) metric,
    ];
    final metric = available.contains(_chosen)
        ? _chosen!
        : (available.isEmpty ? ProgressMetric.bestReps : available.first);
    final points = [
      for (final stats in timeline)
        if (metric.valueOf(stats) != null) (stats: stats, value: metric.valueOf(stats)!),
    ];
    final suggestion = suggestOverload(entries.isEmpty ? null : entries.first);
    final plateau = detectPlateau(entries);
    final dateFormat = DateFormat.yMMMd();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        if (suggestion != null)
          _NoteCard(
            icon: Icons.trending_up_rounded,
            title: 'Next time',
            message: suggestion.message,
          ),
        if (plateau != null)
          _NoteCard(
            icon: Icons.pause_circle_outline_rounded,
            title: 'Progress has stalled',
            message:
                'No new best in the last ${plateau.sessionsSinceBest} sessions '
                '(${plateau.isOneRepMax ? 'est. 1RM ${formatKg(double.parse(plateau.best.toStringAsFixed(1)))} kg' : '${plateau.best.round()} reps'}'
                ' on ${dateFormat.format(plateau.bestDate.toLocal())}). '
                'A lighter week, a different rep range or more rest between sessions can help.',
            tertiary: true,
          ),
        const SizedBox(height: AppSpacing.sm),
        if (available.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<ProgressMetric>(
              showSelectedIcon: false,
              segments: [for (final m in available) ButtonSegment(value: m, label: Text(m.label))],
              selected: {metric},
              onSelectionChanged: (selection) => setState(() => _chosen = selection.first),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(metric.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: LineChart(
              values: [for (final p in points) p.value],
              formatValue: metric.format,
              startLabel: dateFormat.format(points.first.stats.date.toLocal()),
              endLabel: dateFormat.format(points.last.stats.date.toLocal()),
              semanticsLabel:
                  '${metric.title} over ${points.length} sessions, from '
                  '${metric.format(points.first.value)} to ${metric.format(points.last.value)}',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Recent sessions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final entry in entries.take(10))
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              title: Text(dateFormat.format(entry.startedAt.toLocal())),
              subtitle: Text(describeSets(entry.sets).isEmpty ? '—' : describeSets(entry.sets)),
              trailing: Text(
                entry.activityTitle,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.icon,
    required this.title,
    required this.message,
    this.tertiary = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool tertiary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: tertiary ? scheme.tertiaryContainer : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tertiary ? scheme.onTertiaryContainer : scheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: tertiary ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: TextStyle(
                      color: tertiary ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
