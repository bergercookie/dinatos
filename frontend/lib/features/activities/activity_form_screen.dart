import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/activity.dart';
import '../../models/exercise.dart';
import '../../models/routine.dart';
import '../../models/superset.dart';
import '../../models/uid.dart';
import '../exercises/exercise_picker.dart';
import '../exercises/exercises_providers.dart';
import '../routines/routines_providers.dart';
import 'activities_providers.dart';
import 'activities_repository.dart';
import 'live/muscle_distribution_card.dart';
import 'widgets/activity_exercise_card.dart';

/// Create when [activityId] is null, otherwise edit (and `PUT`-replace) that
/// activity's exercises and sets as a whole -- the same full-replace shape
/// `routines` uses.
///
/// Weight/reps/set-type are the only per-set fields this form edits;
/// distance/duration stay whatever they already were (null for a new
/// set) -- a deliberately smaller v1 surface, not an oversight.
class ActivityFormScreen extends ConsumerStatefulWidget {
  const ActivityFormScreen({super.key, this.activityId});

  final int? activityId;

  @override
  ConsumerState<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends ConsumerState<ActivityFormScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _startedAt = DateTime.now();
  DateTime? _endedAt;
  int? _routineId;
  List<ActivityExercise> _exercises = [];
  bool _submitting = false;
  String? _error;
  bool _loadedInitialValues = false;

  bool get _isEditing => widget.activityId != null;

  void _loadFrom(Activity activity) {
    if (_loadedInitialValues) return;
    _loadedInitialValues = true;
    _titleController.text = activity.title;
    _descriptionController.text = activity.description ?? '';
    _startedAt = activity.startedAt.toLocal();
    _endedAt = activity.endedAt?.toLocal();
    _routineId = activity.routineId;
    // Repairs group numbers that aren't a run of neighbours (e.g. from an import).
    _exercises = normalizeSupersets(activity.exercises, activitySupersets);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _startFromRoutine(Routine routine) {
    setState(() {
      _titleController.text = routine.name;
      _routineId = routine.id;
      _exercises = routine.exercises
          .map(
            (we) => ActivityExercise(
              uid: nextUid(),
              exerciseId: we.exerciseId,
              supersetGroup: we.supersetGroup,
              notes: we.notes,
              sets: we.sets
                  .map(
                    (s) => ActivitySet(
                      uid: nextUid(),
                      setType: s.setType,
                      weightKg: s.targetWeightKg,
                      reps: s.targetReps,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList();
    });
  }

  Future<void> _pickStartedAt() async {
    final picked = await _pickDateTime(context, _startedAt);
    if (picked != null) setState(() => _startedAt = picked);
  }

  Future<void> _pickEndedAt() async {
    final picked = await _pickDateTime(context, _endedAt ?? _startedAt);
    if (picked != null) setState(() => _endedAt = picked);
  }

  void _addExercise(Exercise exercise) {
    setState(
      () =>
          _exercises = [..._exercises, ActivityExercise(uid: nextUid(), exerciseId: exercise.id!)],
    );
  }

  void _removeExerciseAt(int index) {
    setState(() => _exercises = removeItem(_exercises, index, activitySupersets));
  }

  void _updateExerciseAt(int index, ActivityExercise updated) {
    setState(() => _exercises = List.of(_exercises)..[index] = updated);
  }

  Future<void> _submit() async {
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
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      startedAt: _startedAt,
      endedAt: _endedAt,
      routineId: _routineId,
      exercises: _exercises,
    );
    final repository = ref.read(activitiesRepositoryProvider);
    try {
      if (_isEditing) {
        await repository.replace(widget.activityId!, activity);
      } else {
        await repository.create(activity);
      }
      ref.invalidate(activityListProvider);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _submitting = true);
    try {
      await ref.read(activitiesRepositoryProvider).delete(widget.activityId!);
      ref.invalidate(activityListProvider);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Edit activity' : 'New activity';
    if (!_isEditing) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ResponsiveBody(child: _buildForm(context)),
      );
    }
    final activityAsync = ref.watch(activityProvider(widget.activityId!));
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Delete activity',
            icon: const Icon(Icons.delete_outline),
            onPressed: _submitting ? null : _delete,
          ),
        ],
      ),
      body: ResponsiveBody(
        child: AsyncValueView(
          value: activityAsync,
          builder: (context, activity) {
            _loadFrom(activity);
            return _buildForm(context);
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final exercisesAsync = ref.watch(exerciseListProvider);
    final dateFormat = DateFormat.yMMMd().add_Hm();
    final labels = supersetLabels([for (final e in _exercises) e.supersetGroup]);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description (optional)'),
          // Grows with what is typed, so a long description never ends up in
          // a tiny box with a thin scrollbar of its own.
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          minLines: 4,
          maxLines: null,
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Started'),
          subtitle: Text(dateFormat.format(_startedAt)),
          trailing: const Icon(Icons.edit_calendar),
          onTap: _pickStartedAt,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ended'),
          subtitle: Text(_endedAt != null ? dateFormat.format(_endedAt!) : 'Not set'),
          trailing: _endedAt != null
              ? IconButton(
                  tooltip: 'Clear ended time',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _endedAt = null),
                )
              : const Icon(Icons.edit_calendar),
          onTap: _pickEndedAt,
        ),
        if (!_isEditing) ...[
          const SizedBox(height: 8),
          Consumer(
            builder: (context, ref, _) {
              final routinesAsync = ref.watch(routineListProvider);
              return routinesAsync.maybeWhen(
                data: (routines) => routines.isEmpty
                    ? const SizedBox.shrink()
                    : MenuAnchor(
                        builder: (context, controller, child) => OutlinedButton.icon(
                          onPressed: () =>
                              controller.isOpen ? controller.close() : controller.open(),
                          icon: const Icon(Icons.content_copy),
                          label: const Text('Start from a saved routine'),
                        ),
                        menuChildren: routines
                            .map(
                              (r) => MenuItemButton(
                                onPressed: () => _startFromRoutine(r),
                                child: Text(r.name),
                              ),
                            )
                            .toList(),
                      ),
                orElse: () => const SizedBox.shrink(),
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        MuscleDistributionCard(exercises: _exercises, catalog: exercisesAsync, showSetCount: true),
        const SizedBox(height: 16),
        Text('Exercises', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < _exercises.length; i++)
          ActivityExerciseCard(
            key: ValueKey(itemKeyOf(uid: _exercises[i].uid, id: _exercises[i].id, index: i)),
            exercise: _exercises[i],
            catalogExercise: exercisesAsync.valueOrNull?.firstWhere(
              (e) => e.id == _exercises[i].exerciseId,
              orElse: () => Exercise(name: '#${_exercises[i].exerciseId}'),
            ),
            supersetLabel: labels[i],
            onChanged: (updated) => _updateExerciseAt(i, updated),
            onRemove: () => _removeExerciseAt(i),
            onLinkWithNext: i + 1 < _exercises.length
                ? () => setState(() => _exercises = linkWithNext(_exercises, i, activitySupersets))
                : null,
            onUnlink: () => setState(() => _exercises = unlink(_exercises, i, activitySupersets)),
            onMoveUp: i > 0
                ? () =>
                      setState(() => _exercises = moveItem(_exercises, i, i - 1, activitySupersets))
                : null,
            onMoveDown: i + 1 < _exercises.length
                ? () =>
                      setState(() => _exercises = moveItem(_exercises, i, i + 1, activitySupersets))
                : null,
          ),
        const SizedBox(height: 8),
        AsyncValueView(
          value: exercisesAsync,
          builder: (context, allExercises) => OutlinedButton.icon(
            onPressed: () async {
              final exercise = await showExercisePicker(context, exercises: allExercises);
              if (exercise != null) _addExercise(exercise);
            },
            icon: const Icon(Icons.add),
            label: const Text('Add exercise'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
