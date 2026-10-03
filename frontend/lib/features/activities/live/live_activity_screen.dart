import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/async_value_view.dart';
import '../../../core/design_tokens.dart';
import '../../../core/widgets/responsive_body.dart';
import '../../../models/activity.dart';
import '../../../models/exercise.dart';
import '../../../models/superset.dart';
import '../../../models/uid.dart';
import '../../exercises/exercise_picker.dart';
import '../../exercises/exercises_providers.dart';
import '../../onboarding/onboarding_overlay.dart';
import '../../progress/exercise_progress_screen.dart';
import '../widgets/activity_exercise_card.dart';
import 'elapsed_timer.dart';
import 'live_session.dart';
import 'muscle_distribution_card.dart';

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

  Future<void> _showStopwatchControls(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(liveActivityProvider.notifier);
    final action = await showModalBottomSheet<_StopwatchAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final paused = ref.read(liveActivityProvider)?.isPaused ?? false;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(paused ? Icons.play_arrow : Icons.pause),
                title: Text(paused ? 'Resume' : 'Pause'),
                onTap: () => Navigator.pop(context, _StopwatchAction.togglePause),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Reset to 00:00'),
                onTap: () => Navigator.pop(context, _StopwatchAction.reset),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Set time...'),
                onTap: () => Navigator.pop(context, _StopwatchAction.setTime),
              ),
            ],
          ),
        );
      },
    );
    switch (action) {
      case _StopwatchAction.togglePause:
        final paused = ref.read(liveActivityProvider)?.isPaused ?? false;
        paused ? notifier.resumeClock() : notifier.pauseClock();
      case _StopwatchAction.reset:
        notifier.resetClock();
      case _StopwatchAction.setTime:
        if (!context.mounted) return;
        final elapsed = await _askForTime(context);
        if (elapsed != null) notifier.setClock(elapsed);
      case null:
        break;
    }
  }

  Future<Duration?> _askForTime(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<Duration>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) {
            void submit() {
              final parsed = parseElapsed(controller.text);
              if (parsed == null) {
                setState(() => error = 'Use m:ss, h:mm:ss or minutes');
              } else {
                Navigator.pop(context, parsed);
              }
            }

            return AlertDialog(
              title: const Text('Set time'),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: 'Elapsed time',
                  hintText: '12:30',
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                TextButton(onPressed: submit, child: const Text('Set')),
              ],
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(liveActivityProvider);

    if (session == null) {
      // Reached directly (e.g. a refreshed page on web) rather than via the
      // activities list's "Start activity" button -- offer to start one
      // instead of showing a blank, broken screen.
      return Scaffold(
        appBar: AppBar(title: const Text('Live workout')),
        body: Center(
          child: FilledButton.icon(
            onPressed: () => ref.read(liveActivityProvider.notifier).start(),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start activity'),
          ),
        ),
      );
    }

    final exercisesAsync = ref.watch(exerciseListProvider);
    final labels = supersetLabels([for (final e in session.exercises) e.supersetGroup]);

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
                    // `until: pausedAt` freezes the display while paused.
                    value: ElapsedTimer(
                      since: session.clockOrigin,
                      until: session.pausedAt,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    trailingIcon: session.isPaused ? Icons.pause_circle_outline : null,
                    onTap: () => _showStopwatchControls(context, ref),
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
            MuscleDistributionCard(exercises: session.exercises, catalog: exercisesAsync),
            const SizedBox(height: AppSpacing.lg),
            Text('Exercises', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < session.exercises.length; i++)
              _LiveExerciseCard(
                key: ValueKey(
                  itemKeyOf(uid: session.exercises[i].uid, id: session.exercises[i].id, index: i),
                ),
                index: i,
                count: session.exercises.length,
                exercise: session.exercises[i],
                supersetLabel: labels[i],
                catalogExercise: exercisesAsync.valueOrNull?.firstWhere(
                  (e) => e.id == session.exercises[i].exerciseId,
                  orElse: () => Exercise(name: '#${session.exercises[i].exerciseId}'),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            AsyncValueView(
              value: exercisesAsync,
              builder: (context, allExercises) => OnboardingTarget(
                id: 'live-add-exercise',
                child: OutlinedButton.icon(
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
            ),
            const SizedBox(height: AppSpacing.xl),
            OnboardingTarget(
              id: 'live-finish',
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(liveActivityProvider.notifier).finish();
                  context.go('/activities/live/summary');
                },
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Finish workout'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StopwatchAction { togglePause, reset, setTime }

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.trailingIcon,
  });

  final IconData icon;
  final String label;
  final Widget value;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Icon(trailingIcon, size: 16, color: scheme.onSurfaceVariant),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              value,
            ],
          ),
        ),
      ),
    );
  }
}

/// One exercise in the live workout: [ActivityExerciseCard] plus what only
/// this screen knows -- the exercise's history (for "last time" and the
/// suggestion) and records (for trophies), both fetched from the server and
/// simply absent while loading or when it can't be reached, so logging a set
/// never waits on, or fails because of, the network.
class _LiveExerciseCard extends ConsumerWidget {
  const _LiveExerciseCard({
    super.key,
    required this.index,
    required this.count,
    required this.exercise,
    required this.catalogExercise,
    required this.supersetLabel,
  });

  final int index;
  final int count;
  final ActivityExercise exercise;
  final Exercise? catalogExercise;
  final String? supersetLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(liveActivityProvider.notifier);
    return ActivityExerciseCard(
      exercise: exercise,
      catalogExercise: catalogExercise,
      history: ref.watch(exerciseHistoryProvider(exercise.exerciseId)).valueOrNull,
      records: ref.watch(exerciseRecordsProvider(exercise.exerciseId)).valueOrNull,
      supersetLabel: supersetLabel,
      onChanged: (updated) => notifier.updateExerciseAt(index, updated),
      onRemove: () => notifier.removeExerciseAt(index),
      onLinkWithNext: index + 1 < count ? () => notifier.linkExerciseWithNext(index) : null,
      onUnlink: () => notifier.unlinkExercise(index),
      onMoveUp: index > 0 ? () => notifier.moveExercise(index, index - 1) : null,
      onMoveDown: index + 1 < count ? () => notifier.moveExercise(index, index + 1) : null,
      onViewProgress: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExerciseProgressScreen(exerciseId: exercise.exerciseId),
        ),
      ),
    );
  }
}
