import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_exception.dart';
import '../../../core/design_tokens.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/responsive_body.dart';
import '../../../models/activity.dart';
import '../../../models/exercise_records.dart';
import '../../../models/muscle_group.dart';
import '../../exercises/exercises_providers.dart';
import '../../exercises/exercises_repository.dart';
import '../../calendar/planned_workouts_providers.dart';
import '../activities_providers.dart';
import '../activities_repository.dart';
import 'elapsed_timer.dart';
import 'live_session.dart';
import 'muscle_distribution_card.dart';

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

/// What the end-of-workout record check found. [unavailable] means it could
/// not be done at all (the server couldn't be reached), which is not the same
/// as "no records" and is reported as such.
class _RecordsOutcome {
  const _RecordsOutcome({this.records = const [], this.unavailable = false});

  final List<_NewRecord> records;
  final bool unavailable;
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
  Future<_RecordsOutcome>? _recordsFuture;

  @override
  void initState() {
    super.initState();
    final session = ref.read(liveActivityProvider);
    if (session != null && !session.isSaved) {
      _titleController.text =
          session.pendingTitle ??
          session.routineName ??
          'Workout on ${DateFormat.yMMMd().format(session.startedAt)}';
      _recordsFuture = _loadNewRecords(session);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// For each exercise actually performed this session, compares its sets
  /// here against the caller's own all-time best (`GET
  /// /exercises/{id}/records`, fetched fresh since nothing from this
  /// session is saved yet to have changed it) and reports a new record for
  /// whichever of heaviest weight / most reps was just beaten -- by the same
  /// rules the live screen's trophies use ([detectSetRecords]).
  ///
  /// Needs the server, and a workout finished with no connection is exactly
  /// when it hasn't got it: that comes back as [_RecordsOutcome.unavailable]
  /// rather than as a (false) "no new records".
  Future<_RecordsOutcome> _loadNewRecords(LiveActivitySession session) async {
    final repository = ref.read(exercisesRepositoryProvider);
    final names = <int?, String>{};
    try {
      for (final exercise in await ref.read(exerciseListProvider.future)) {
        names[exercise.id] = exercise.name;
      }
    } catch (_) {
      // Only names are lost; "Exercise #12" will do.
    }
    final records = <_NewRecord>[];
    try {
      for (final exerciseId in session.exercises.map((e) => e.exerciseId).toSet()) {
        final sets = session.exercises
            .where((e) => e.exerciseId == exerciseId)
            .expand((e) => e.completedSets)
            .toList();
        final prior = await repository.getRecords(exerciseId);
        final flags = detectSetRecords(sets, prior, requirePrior: false);
        final name = names[exerciseId] ?? 'Exercise #$exerciseId';
        final weights = [
          for (var i = 0; i < sets.length; i++)
            if (flags[i].weight) sets[i].weightKg!,
        ];
        final reps = [
          for (var i = 0; i < sets.length; i++)
            if (flags[i].reps) sets[i].reps!,
        ];
        if (weights.isNotEmpty) {
          records.add(
            _NewRecord(
              exerciseName: name,
              description: 'New heaviest weight: ${weights.last.toStringAsFixed(1)} kg',
            ),
          );
        }
        if (reps.isNotEmpty) {
          records.add(_NewRecord(exerciseName: name, description: 'New best: ${reps.last} reps'));
        }
      }
    } catch (_) {
      return const _RecordsOutcome(unavailable: true);
    }
    return _RecordsOutcome(records: records);
  }

  Future<void> _save(LiveActivitySession session) async {
    // After an attempt that may have reached the server the title is frozen,
    // so the retry is recognisably the same save (see `pendingTitle`).
    final title = session.pendingTitle ?? _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final notifier = ref.read(liveActivityProvider.notifier);
    final activity = Activity(
      title: title,
      startedAt: session.startedAt,
      endedAt: session.endedAt ?? DateTime.now(),
      exercises: session.exercises,
      routineId: session.routineId,
      plannedWorkoutId: session.plannedWorkoutId,
    );
    try {
      final saved = await ref.read(activitiesRepositoryProvider).create(activity);
      ref.invalidate(activityListProvider);
      if (session.plannedWorkoutId != null) ref.invalidate(plannedWorkoutListProvider);
      if (mounted) notifier.markSaved(activityId: saved.id!, title: saved.title);
    } on ApiException catch (error) {
      // No HTTP status means no response: the workout may or may not have been
      // stored. A status means the server looked at it and said no.
      if (error.statusCode == null) {
        notifier.markSaveUncertain(title);
        setState(
          () => _error =
              '${error.message} Your workout is kept on this device -- try saving again '
              'once you are back online.',
        );
      } else {
        notifier.clearSaveUncertainty();
        setState(() => _error = error.message);
      }
    } catch (_) {
      // E.g. a response that could not be read: as unknown as a dropped one.
      notifier.markSaveUncertain(title);
      setState(
        () => _error =
            'Something went wrong while saving. Your workout is kept on this device -- try again.',
      );
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
                enabled: session.pendingTitle == null,
                decoration: InputDecoration(
                  labelText: 'Title',
                  helperText: session.pendingTitle == null
                      ? null
                      : 'The last attempt may have gone through, so the title is locked '
                            'to keep a retry from saving the workout twice.',
                  helperMaxLines: 3,
                ),
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
            MuscleDistributionCard(
              exercises: session.exercises,
              catalog: exercisesAsync,
              footerBuilder: (context, volumes) => Text(
                'Main muscles: ${_describeMainMuscles(volumes)}',
                style: Theme.of(context).textTheme.bodyMedium,
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
              FutureBuilder<_RecordsOutcome>(
                future: _recordsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final outcome = snapshot.data ?? const _RecordsOutcome(unavailable: true);
                  final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
                  if (outcome.unavailable) {
                    return Row(
                      children: [
                        Icon(Icons.cloud_off_outlined, color: muted.color),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Could not check for new records without a connection.',
                            style: muted,
                          ),
                        ),
                        // Only before saving: afterwards the server's "best" already
                        // includes this workout, and nothing would read as a record.
                        if (savedActivityId == null)
                          TextButton(
                            onPressed: () {
                              final retry = _loadNewRecords(session);
                              setState(() {
                                _recordsFuture = retry;
                              });
                            },
                            child: const Text('Retry'),
                          ),
                      ],
                    );
                  }
                  if (outcome.records.isEmpty) {
                    return Text('No new records this time — keep at it.', style: muted);
                  }
                  return Column(
                    children: outcome.records
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
