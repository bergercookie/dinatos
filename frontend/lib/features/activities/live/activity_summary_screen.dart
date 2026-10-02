import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_exception.dart';
import '../../../core/async_value_view.dart';
import '../../../core/design_tokens.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/responsive_body.dart';
import '../../../models/activity.dart';
import '../../../models/muscle_group.dart';
import '../../exercises/exercises_providers.dart';
import '../../exercises/exercises_repository.dart';
import '../activities_providers.dart';
import '../activities_repository.dart';
import 'elapsed_timer.dart';
import 'live_session.dart';
import 'muscle_radar_chart.dart';
import 'muscle_volume.dart';

/// A plain-language "chest, shoulders, triceps" from a muscle-emphasis map
/// -- the same data the radar chart plots, read out as the handful of
/// muscles that got the most volume, for a person who just wants the
/// answer in words rather than reading a chart.
String _describeMainMuscles(Map<MuscleGroup, double> volumes) {
  if (volumes.isEmpty) return 'None yet';
  final sorted = volumes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(3).map((entry) => entry.key.label).join(', ');
}

class _NewRecord {
  const _NewRecord({required this.exerciseName, required this.description});

  final String exerciseName;
  final String description;
}

/// Shown once the person taps "Finish workout" -- a recap of the just-
/// finished [LiveActivitySession] (duration, volume, muscles targeted, any
/// new personal records) with a title field, then an explicit save that
/// finally does the one `POST /activities` the whole session was built
/// towards (the backend has no in-progress/draft activity concept -- see
/// AGENTS.md -- so nothing is persisted before this).
class ActivitySummaryScreen extends ConsumerStatefulWidget {
  const ActivitySummaryScreen({super.key});

  @override
  ConsumerState<ActivitySummaryScreen> createState() => _ActivitySummaryScreenState();
}

class _ActivitySummaryScreenState extends ConsumerState<ActivitySummaryScreen> {
  final _titleController = TextEditingController();
  bool _submitting = false;
  String? _error;
  Future<List<_NewRecord>>? _recordsFuture;

  @override
  void initState() {
    super.initState();
    final session = ref.read(liveActivityProvider);
    if (session != null && !session.isSaved) {
      _titleController.text = 'Workout on ${DateFormat.yMMMd().format(session.startedAt)}';
      _recordsFuture = _loadNewRecords(session);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// For each exercise actually performed this session, compares its best
  /// set here against the caller's own all-time best (`GET
  /// /exercises/{id}/records`, fetched fresh since nothing from this
  /// session is saved yet to have changed it) and reports a new record for
  /// whichever of heaviest weight / most reps was just beaten.
  Future<List<_NewRecord>> _loadNewRecords(LiveActivitySession session) async {
    final repository = ref.read(exercisesRepositoryProvider);
    final catalog = await ref.read(exerciseListProvider.future);
    final catalogById = {for (final exercise in catalog) exercise.id: exercise};
    final records = <_NewRecord>[];

    final exerciseIds = session.exercises.map((e) => e.exerciseId).toSet();
    for (final exerciseId in exerciseIds) {
      final sets = session.exercises.where((e) => e.exerciseId == exerciseId).expand((e) => e.sets);
      final weights = sets.map((s) => s.weightKg).whereType<double>().toList();
      final reps = sets.map((s) => s.reps).whereType<int>().toList();
      if (weights.isEmpty && reps.isEmpty) continue;

      final priorBest = await repository.getRecords(exerciseId);
      final name = catalogById[exerciseId]?.name ?? 'Exercise #$exerciseId';

      if (weights.isNotEmpty) {
        final sessionBestWeight = weights.reduce(math.max);
        if (priorBest.maxWeightKg == null || sessionBestWeight > priorBest.maxWeightKg!) {
          records.add(
            _NewRecord(
              exerciseName: name,
              description: 'New heaviest weight: ${sessionBestWeight.toStringAsFixed(1)} kg',
            ),
          );
        }
      }
      if (reps.isNotEmpty) {
        final sessionBestReps = reps.reduce(math.max);
        if (priorBest.maxReps == null || sessionBestReps > priorBest.maxReps!) {
          records.add(
            _NewRecord(exerciseName: name, description: 'New best: $sessionBestReps reps'),
          );
        }
      }
    }
    return records;
  }

  Future<void> _save(LiveActivitySession session) async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final activity = Activity(
      title: _titleController.text.trim(),
      startedAt: session.startedAt,
      endedAt: session.endedAt ?? DateTime.now(),
      exercises: session.exercises,
    );
    try {
      final saved = await ref.read(activitiesRepositoryProvider).create(activity);
      ref.invalidate(activityListProvider);
      if (mounted) {
        ref
            .read(liveActivityProvider.notifier)
            .markSaved(activityId: saved.id!, title: saved.title);
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _done() {
    ref.read(liveActivityProvider.notifier).discard();
    context.go('/activities');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(liveActivityProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workout summary')),
        body: const Center(child: Text('No workout to summarize.')),
      );
    }

    final exercisesAsync = ref.watch(exerciseListProvider);
    final endedAt = session.endedAt ?? DateTime.now();
    final savedActivityId = session.savedActivityId;
    final savedTitle = session.savedTitle;

    return Scaffold(
      appBar: AppBar(title: Text(savedActivityId != null ? 'Workout saved' : 'Workout summary')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            if (savedTitle != null)
              Text(savedTitle, style: Theme.of(context).textTheme.headlineSmall)
            else
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _SummaryStat(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: formatElapsed(endedAt.difference(session.startedAt)),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _SummaryStat(
                    icon: Icons.fitness_center,
                    label: 'Volume lifted',
                    value: '${session.totalVolumeKg.toStringAsFixed(0)} kg',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _SummaryStat(
                    icon: Icons.checklist_rounded,
                    label: 'Sets',
                    value: '${session.totalSets}',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _SummaryStat(
                    icon: Icons.repeat_rounded,
                    label: 'Reps',
                    value: '${session.totalReps}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${DateFormat.yMMMd().add_Hm().format(session.startedAt)} '
              '– ${DateFormat.Hm().format(endedAt)}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
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
                      builder: (context, catalog) {
                        final volumes = computeMuscleVolumes(session.exercises, catalog);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MuscleRadarChart(volumes: volumes),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Main muscles: ${_describeMainMuscles(volumes)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Null only when this widget was (re)mounted onto an already-
            // saved session (e.g. a browser back button) -- the moment to
            // show new records is right after saving, within that same
            // mounted instance, where `_recordsFuture` is always set below.
            if (_recordsFuture != null) ...[
              Text('New records', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              FutureBuilder<List<_NewRecord>>(
                future: _recordsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final records = snapshot.data ?? [];
                  if (records.isEmpty) {
                    return Text(
                      'No new records this time — keep at it.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    );
                  }
                  return Column(
                    children: records
                        .map(
                          (record) => Card(
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: ListTile(
                              leading: Icon(
                                Icons.emoji_events,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                              title: Text(record.exerciseName),
                              subtitle: Text(record.description),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (savedActivityId == null)
              FilledButton(
                onPressed: _submitting ? null : () => _save(session),
                child: const Text('Save workout'),
              )
            else ...[
              FilledButton(onPressed: _done, child: const Text('Done')),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () {
                  ref.read(liveActivityProvider.notifier).discard();
                  context.go('/activities/$savedActivityId');
                },
                child: const Text('View activity'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

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
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
