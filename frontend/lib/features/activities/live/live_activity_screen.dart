import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/async_value_view.dart';
import '../../../core/design_tokens.dart';
import '../../../core/widgets/responsive_body.dart';
import '../../../models/exercise.dart';
import '../../exercises/exercise_picker.dart';
import '../../exercises/exercises_providers.dart';
import '../widgets/activity_exercise_card.dart';
import 'elapsed_timer.dart';
import 'live_session.dart';
import 'muscle_radar_chart.dart';
import 'muscle_volume.dart';

/// The interactive "I'm at the gym right now" workflow -- in contrast to
/// [ActivityFormScreen]'s after-the-fact log entry, sets are added one at a
/// time as they're actually performed, with a running clock, total volume
/// and muscle-emphasis chart updating live. See `live_session.dart` for the
/// state this reads/writes.
class LiveActivityScreen extends ConsumerWidget {
  const LiveActivityScreen({super.key});

  Future<bool> _confirmDiscard(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this workout?'),
        content: const Text('Everything logged so far will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(liveActivityProvider);

    if (session == null) {
      // Reached directly (e.g. a refreshed page on web) rather than via the
      // activities list's "Start workout" button -- offer to start one
      // instead of showing a blank, broken screen.
      return Scaffold(
        appBar: AppBar(title: const Text('Live workout')),
        body: Center(
          child: FilledButton.icon(
            onPressed: () => ref.read(liveActivityProvider.notifier).start(),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start workout'),
          ),
        ),
      );
    }

    final exercisesAsync = ref.watch(exerciseListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live workout'),
        leading: IconButton(
          tooltip: 'Discard workout',
          icon: const Icon(Icons.close),
          onPressed: () async {
            if (await _confirmDiscard(context)) {
              ref.read(liveActivityProvider.notifier).discard();
              if (context.mounted) context.go('/activities');
            }
          },
        ),
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.timer_outlined,
                    label: 'Time',
                    value: ElapsedTimer(
                      since: session.startedAt,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatTile(
                    icon: Icons.checklist_rounded,
                    label: 'Sets done',
                    value: Text(
                      '${session.totalSets}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatTile(
                    icon: Icons.fitness_center,
                    label: 'Volume lifted',
                    value: Text(
                      '${session.totalVolumeKg.toStringAsFixed(0)} kg',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Muscles targeted', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    AsyncValueView(
                      value: exercisesAsync,
                      builder: (context, catalog) => MuscleRadarChart(
                        volumes: computeMuscleVolumes(session.exercises, catalog),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Exercises', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < session.exercises.length; i++)
              ActivityExerciseCard(
                exercise: session.exercises[i],
                catalogExercise: exercisesAsync.valueOrNull?.firstWhere(
                  (e) => e.id == session.exercises[i].exerciseId,
                  orElse: () => Exercise(name: '#${session.exercises[i].exerciseId}'),
                ),
                onChanged: (updated) =>
                    ref.read(liveActivityProvider.notifier).updateExerciseAt(i, updated),
                onRemove: () => ref.read(liveActivityProvider.notifier).removeExerciseAt(i),
              ),
            const SizedBox(height: AppSpacing.sm),
            AsyncValueView(
              value: exercisesAsync,
              builder: (context, allExercises) => OutlinedButton.icon(
                onPressed: () async {
                  final exercise = await showExercisePicker(context, exercises: allExercises);
                  if (exercise != null) {
                    ref.read(liveActivityProvider.notifier).addExercise(exercise.id!);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add exercise'),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () {
                ref.read(liveActivityProvider.notifier).finish();
                context.go('/activities/live/summary');
              },
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Finish workout'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            value,
          ],
        ),
      ),
    );
  }
}
