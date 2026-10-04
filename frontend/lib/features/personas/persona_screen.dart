import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/radar_chart.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/activity.dart';
import '../../models/exercise.dart';
import '../../models/measurement.dart';
import '../activities/activities_providers.dart';
import '../measurements/measurements_providers.dart';
import '../profile/profile_providers.dart';
import '../stats/stats_screen.dart' show fullCatalogProvider;
import '../stats/training_stats.dart' show StatsRange;
import 'persona_profiles.dart';
import 'persona_scoring.dart';

/// "Which athlete do you resemble?": a radar chart with one spoke per
/// persona and two overlaid shapes -- how closely the person's *body*
/// measurements match each persona, and how closely their *training* does --
/// so the gap between the two shows whether they train like the athlete they
/// want to become. Everything is derived on the device from the data the app
/// already has; there is no endpoint behind it.
class PersonaScreen extends ConsumerStatefulWidget {
  const PersonaScreen({super.key});

  @override
  ConsumerState<PersonaScreen> createState() => _PersonaScreenState();
}

class _PersonaScreenState extends ConsumerState<PersonaScreen> {
  StatsRange _range = StatsRange.quarter;
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final activities = ref.watch(activityListProvider);
    final measurements = ref.watch(measurementListProvider);
    // Both of these only sharpen the result: show what there is while they
    // load, or if they fail.
    final catalog = ref.watch(fullCatalogProvider).valueOrNull ?? const <Exercise>[];
    final heightCm = ref.watch(profileProvider).valueOrNull?.heightCm;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Athlete match'),
        leading: BackButton(onPressed: () => context.go('/activities/stats')),
      ),
      body: ResponsiveBody(
        child: AsyncValueView<List<Activity>>(
          value: activities,
          onRetry: () => ref.invalidate(activityListProvider),
          builder: (context, activityData) => AsyncValueView<List<BodyMeasurement>>(
            value: measurements,
            onRetry: () => ref.invalidate(measurementListProvider),
            builder: (context, measurementData) {
              final analysis = PersonaAnalysis.compute(
                activities: activityData,
                measurements: measurementData,
                catalog: catalog,
                heightCm: heightCm,
                range: _range,
              );
              final selected = _selected(analysis);
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: [
                  _Headline(analysis: analysis),
                  const SizedBox(height: AppSpacing.sm),
                  _RadarCard(
                    analysis: analysis,
                    range: _range,
                    onRange: (r) => setState(() => _range = r),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Picker(
                    analysis: analysis,
                    selected: selected,
                    onSelected: (id) => setState(() => _selectedId = id),
                  ),
                  if (selected != null) _PersonaDetail(match: selected, analysis: analysis),
                  const _HowItWorks(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The persona the person picked, else the best overall match, else the
  /// first one -- so the detail card is never empty.
  PersonaMatch? _selected(PersonaAnalysis analysis) {
    for (final m in analysis.matches) {
      if (m.persona.id == _selectedId) return m;
    }
    return analysis.bestBody ?? analysis.bestTraining ?? analysis.matches.firstOrNull;
  }
}

String _percent(double score) => '${score.round()}%';

class _Headline extends StatelessWidget {
  const _Headline({required this.analysis});

  final PersonaAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final bestBody = analysis.bestBody;
    final bestTraining = analysis.bestTraining;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget line(IconData icon, Color color, String label, PersonaMatch? best, double? score) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: best == null
                  ? Text(label)
                  : Text.rich(
                      TextSpan(
                        text: label,
                        children: [
                          TextSpan(
                            text: best.persona.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: ' (${_percent(score!)} match)'),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What do you resemble?', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            line(
              Icons.accessibility_new,
              scheme.primary,
              bestBody == null
                  ? 'Not enough measurements to say what your body resembles yet.'
                  : 'Your body looks most like a ',
              bestBody,
              bestBody?.bodyScore,
            ),
            line(
              Icons.fitness_center,
              scheme.tertiary,
              bestTraining == null
                  ? 'Log more training (about ${minTrainingUnits.round()} sets) to see what '
                        'your training resembles.'
                  : 'Your training looks most like a ',
              bestTraining,
              bestTraining?.trainingScore,
            ),
            if (analysis.missingInputs.isNotEmpty && analysis.bodyFeatures.length < 7)
              Text(
                'Add ${_list(analysis.missingInputs)} to your measurements to sharpen the '
                'body match.',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

String _list(List<String> items) {
  if (items.length <= 2) return items.join(' and ');
  return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

class _RadarCard extends StatelessWidget {
  const _RadarCard({required this.analysis, required this.range, required this.onRange});

  final PersonaAnalysis analysis;
  final StatsRange range;
  final ValueChanged<StatsRange> onRange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final body = RadarSeries(
      name: 'Your body',
      values: [for (final m in analysis.matches) m.bodyScore],
      color: scheme.primary,
    );
    final training = RadarSeries(
      name: 'Your training',
      values: [for (final m in analysis.matches) m.trainingScore],
      color: scheme.tertiary,
    );
    final summary = StringBuffer('Match with each athlete, 0 to 100. ');
    for (final m in analysis.matches) {
      summary.write('${m.persona.shortName}: ');
      summary.write(
        'body ${m.bodyScore == null ? 'unknown' : _percent(m.bodyScore!)}, '
        'training ${m.trainingScore == null ? 'unknown' : _percent(m.trainingScore!)}. ',
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Body vs training', style: textTheme.titleMedium),
            Text(
              'The further out a corner, the closer the match',
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            RadarChart(
              labels: [for (final p in personas) p.shortName],
              series: [body, training],
              semanticsLabel: summary.toString().trim(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                _LegendDot(color: body.color, label: body.name),
                _LegendDot(color: training.color, label: training.name),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Training is judged over:',
              style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<StatsRange>(
              showSelectedIcon: false,
              segments: [
                for (final r in StatsRange.values) ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {range},
              onSelectionChanged: (s) => onRange(s.first),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.analysis, required this.selected, required this.onSelected});

  final PersonaAnalysis analysis;
  final PersonaMatch? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Which athlete do you want to train towards?', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final m in analysis.matches)
                  ChoiceChip(
                    label: Text(m.persona.shortName),
                    selected: m.persona.id == selected?.persona.id,
                    onSelected: (_) => onSelected(m.persona.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonaDetail extends StatelessWidget {
  const _PersonaDetail({required this.match, required this.analysis});

  final PersonaMatch match;
  final PersonaAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final persona = match.persona;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(persona.name, style: textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(persona.summary),
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader(
              icon: Icons.accessibility_new,
              color: scheme.primary,
              title: 'Body',
              score: match.bodyScore,
            ),
            if (match.bodyRows.isEmpty)
              const Text('No measurements to compare yet.')
            else ...[
              if (match.bodyScore == null)
                Text(
                  'Only ${match.bodyRows.length} of ${persona.body.length} measurements are '
                  'known: not enough for a match, but here is how they compare.',
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              for (final row in match.bodyRows) _BodyRowTile(row: row),
            ],
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader(
              icon: Icons.fitness_center,
              color: scheme.tertiary,
              title: 'Training',
              score: match.trainingScore,
            ),
            if (!analysis.training.isEnough)
              const Text('Log more workouts in this period to compare your training.')
            else ...[
              _TrainingAdvice(match: match),
              const SizedBox(height: AppSpacing.sm),
              for (final focus in TrainingFocus.values)
                _TrainingRowTile(row: match.trainingRows.firstWhere((r) => r.focus == focus)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.score,
  });

  final IconData icon;
  final Color color;
  final String title;
  final double? score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (score != null)
            Text(
              '${_percent(score!)} match',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
            ),
        ],
      ),
    );
  }
}

class _BodyRowTile extends StatelessWidget {
  const _BodyRowTile({required this.row});

  final BodyRow row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final feature = row.feature;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(feature.label)),
              Text(
                'You ${feature.format(row.you)} · typical ${feature.format(row.ideal)}',
                style: textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(
            value: row.closeness,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: scheme.primary,
            semanticsLabel: '${feature.label} closeness',
            semanticsValue: _percent(100 * row.closeness),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(feature.hint, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _TrainingAdvice extends StatelessWidget {
  const _TrainingAdvice({required this.match});

  final PersonaMatch match;

  @override
  Widget build(BuildContext context) {
    final more = match.trainingRows.where((r) => r.gap > 0.05).toList()
      ..sort((a, b) => b.gap.compareTo(a.gap));
    final less = match.trainingRows.where((r) => r.gap < -0.05).toList()
      ..sort((a, b) => a.gap.compareTo(b.gap));
    final name = match.persona.shortName.toLowerCase();
    final String text;
    if (more.isEmpty && less.isEmpty) {
      text = 'Your training mix is already close to a $name\'s.';
    } else {
      text = [
        if (more.isNotEmpty)
          'To train more like a $name, do more ${more.take(2).map((r) => r.focus.label.toLowerCase()).join(' and ')}.',
        if (less.isNotEmpty)
          'You could do less ${less.take(2).map((r) => r.focus.label.toLowerCase()).join(' and ')}.',
      ].join(' ');
    }
    return Text(text);
  }
}

class _TrainingRowTile extends StatelessWidget {
  const _TrainingRowTile({required this.row});

  final TrainingRow row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    String pct(double v) => '${(100 * v).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(row.focus.label)),
              Text('You ${pct(row.you)} · typical ${pct(row.ideal)}', style: textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Two thin bars on one track: yours, and the persona's for reference.
          LinearProgressIndicator(
            value: row.you,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: scheme.tertiary,
            semanticsLabel: '${row.focus.label} share of your training',
            semanticsValue: pct(row.you),
          ),
          const SizedBox(height: 3),
          LinearProgressIndicator(
            value: row.ideal,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
            color: scheme.outline,
            semanticsLabel: '${row.focus.label} share of a typical athlete\'s training',
            semanticsValue: pct(row.ideal),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            row.focus.description,
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text('How this works', style: textTheme.titleMedium),
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'This is a fun, best-effort comparison, not sports science. Each athlete is a '
            'rough archetype with a typical body and a typical training mix.',
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Body: your latest measurements are turned into ratios (muscularity from weight, '
            'body fat and height; waist, shoulders, thigh and arm against height or waist) and '
            'compared with each archetype. The closer a ratio is to the archetype\'s, the more '
            'it counts towards the match; height counts for less. You need at least '
            '$minBodyFeatures of them.',
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Training: every working set (warm-ups are ignored) in the chosen period is put in '
            'one of five groups by its weight, reps, distance, time and exercise name. Cardio '
            'counts one set per 3 minutes. The match is how much your mix overlaps the '
            'archetype\'s.',
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'The reference bodies are generic adult-male proportions (the app doesn\'t know '
            'your sex), so treat the body match as a rough guide, especially for women and '
            'for anyone far from those averages. A lean-and-light frame resembling a distance '
            'runner is not a verdict on what you should train.',
          ),
        ],
      ),
    );
  }
}
