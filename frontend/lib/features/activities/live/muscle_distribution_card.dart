import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async_value_view.dart';
import '../../../core/design_tokens.dart';
import '../../../models/activity.dart';
import '../../../models/exercise.dart';
import '../../../models/muscle_group.dart';
import 'muscle_radar_chart.dart';
import 'muscle_volume.dart';

/// The "Muscles targeted" card: a [MuscleRadarChart] of the muscle
/// distribution of [exercises], plus (when [showSetCount] is set) the total
/// number of sets in the header. Shared by the live workout page and the
/// routine/activity editing forms so they all show the same thing.
class MuscleDistributionCard extends StatelessWidget {
  const MuscleDistributionCard({
    super.key,
    required this.exercises,
    required this.catalog,
    this.showSetCount = false,
    this.footerBuilder,
  });

  final List<ActivityExercise> exercises;

  /// The exercise catalog, still loading or failed as an [AsyncValue] --
  /// [AsyncValueView] shows the usual spinner/error in that case.
  final AsyncValue<List<Exercise>> catalog;
  final bool showSetCount;

  /// Optional extra content under the chart, given the computed volumes.
  final Widget Function(BuildContext context, Map<MuscleGroup, double> volumes)? footerBuilder;

  @override
  Widget build(BuildContext context) {
    final totalSets = exercises.fold<int>(0, (sum, e) => sum + e.completedSets.length);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Muscles targeted', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (showSetCount)
                  Text(
                    '$totalSets ${totalSets == 1 ? 'set' : 'sets'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AsyncValueView(
              value: catalog,
              builder: (context, exercisesCatalog) {
                final volumes = computeMuscleVolumes(exercises, exercisesCatalog);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MuscleRadarChart(volumes: volumes),
                    if (footerBuilder != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      footerBuilder!(context, volumes),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
