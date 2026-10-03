import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/activity.dart';
import '../../models/exercise.dart';
import '../../models/set_type.dart';
import '../../models/routine.dart';
import '../activities/live/muscle_distribution_card.dart';
import '../onboarding/onboarding_overlay.dart';
import '../exercises/exercise_picker.dart';
import '../exercises/exercises_providers.dart';
import 'routines_providers.dart';
import 'routines_repository.dart';

/// Create when [routineId] is null, otherwise edit (and `PUT`-replace) that
/// routine's exercises and sets as a whole.
class RoutineFormScreen extends ConsumerStatefulWidget {
  const RoutineFormScreen({super.key, this.routineId});

  final int? routineId;

  @override
  ConsumerState<RoutineFormScreen> createState() => _RoutineFormScreenState();
}

class _RoutineFormScreenState extends ConsumerState<RoutineFormScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<RoutineExercise> _exercises = [];
  bool _submitting = false;
  String? _error;
  bool _loadedInitialValues = false;

  bool get _isEditing => widget.routineId != null;

  void _loadFrom(Routine routine) {
    if (_loadedInitialValues) return;
    _loadedInitialValues = true;
    _nameController.text = routine.name;
    _descriptionController.text = routine.description ?? '';
    _exercises = List.of(routine.exercises);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _addExercise(Exercise exercise) {
    setState(() {
      _exercises = [..._exercises, RoutineExercise(exerciseId: exercise.id!)];
    });
  }

  void _removeExerciseAt(int index) {
    setState(() => _exercises = List.of(_exercises)..removeAt(index));
  }

  void _updateExerciseAt(int index, RoutineExercise updated) {
    setState(() => _exercises = List.of(_exercises)..[index] = updated);
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final routine = Routine(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      exercises: _exercises,
    );
    final repository = ref.read(routinesRepositoryProvider);
    try {
      if (_isEditing) {
        await repository.replace(widget.routineId!, routine);
      } else {
        await repository.create(routine);
      }
      ref.invalidate(routineListProvider);
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
      await ref.read(routinesRepositoryProvider).delete(widget.routineId!);
      ref.invalidate(routineListProvider);
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
    final title = _isEditing ? 'Edit routine' : 'New routine';
    if (!_isEditing) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ResponsiveBody(child: _buildForm(context)),
      );
    }
    final routineAsync = ref.watch(routineProvider(widget.routineId!));
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Delete routine',
            icon: const Icon(Icons.delete_outline),
            onPressed: _submitting ? null : _delete,
          ),
        ],
      ),
      body: ResponsiveBody(
        child: AsyncValueView(
          value: routineAsync,
          builder: (context, routine) {
            _loadFrom(routine);
            return _buildForm(context);
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final exercisesAsync = ref.watch(exerciseListProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description (optional)'),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        MuscleDistributionCard(
          exercises: _exercises.map(_asActivityExercise).toList(),
          catalog: exercisesAsync,
          showSetCount: true,
        ),
        const SizedBox(height: 16),
        Text('Exercises', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < _exercises.length; i++)
          _RoutineExerciseCard(
            exercise: _exercises[i],
            exerciseName: exercisesAsync.valueOrNull
                ?.firstWhere(
                  (e) => e.id == _exercises[i].exerciseId,
                  orElse: () => Exercise(name: '#${_exercises[i].exerciseId}'),
                )
                .name,
            onChanged: (updated) => _updateExerciseAt(i, updated),
            onRemove: () => _removeExerciseAt(i),
          ),
        const SizedBox(height: 8),
        AsyncValueView(
          value: exercisesAsync,
          builder: (context, allExercises) => OnboardingTarget(
            id: 'routine-add-exercise',
            child: OutlinedButton.icon(
              onPressed: () async {
                final exercise = await showExercisePicker(context, exercises: allExercises);
                if (exercise != null) _addExercise(exercise);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
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

/// A routine's planned sets, shaped as an activity's so the shared muscle
/// distribution can score them. A set with no target reps still counts as
/// one unit of work: a routine being built is mostly sets with no targets
/// filled in yet, and it should still show which muscles it hits.
ActivityExercise _asActivityExercise(RoutineExercise exercise) => ActivityExercise(
  exerciseId: exercise.exerciseId,
  sets: [
    for (final set in exercise.sets)
      ActivitySet(weightKg: set.targetWeightKg, reps: set.targetReps ?? 1),
  ],
);

class _RoutineExerciseCard extends StatelessWidget {
  const _RoutineExerciseCard({
    required this.exercise,
    required this.exerciseName,
    required this.onChanged,
    required this.onRemove,
  });

  final RoutineExercise exercise;
  final String? exerciseName;
  final ValueChanged<RoutineExercise> onChanged;
  final VoidCallback onRemove;

  void _addSet() {
    onChanged(exercise.copyWith(sets: [...exercise.sets, const RoutineSet()]));
  }

  void _removeSetAt(int index) {
    onChanged(exercise.copyWith(sets: List.of(exercise.sets)..removeAt(index)));
  }

  void _updateSetAt(int index, RoutineSet updated) {
    onChanged(exercise.copyWith(sets: List.of(exercise.sets)..[index] = updated));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exerciseName ?? '#${exercise.exerciseId}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove exercise',
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
            for (var i = 0; i < exercise.sets.length; i++)
              _SetRow(
                index: i,
                set: exercise.sets[i],
                onChanged: (updated) => _updateSetAt(i, updated),
                onRemove: () => _removeSetAt(i),
              ),
            TextButton.icon(
              onPressed: _addSet,
              icon: const Icon(Icons.add),
              label: const Text('Add set'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.set,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final RoutineSet set;
  final ValueChanged<RoutineSet> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('${index + 1}.'),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: set.targetWeightKg?.toString(),
            decoration: const InputDecoration(labelText: 'kg', isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) => onChanged(set.copyWith(targetWeightKg: double.tryParse(value))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: set.targetReps?.toString(),
            decoration: const InputDecoration(labelText: 'reps', isDense: true),
            keyboardType: TextInputType.number,
            onChanged: (value) => onChanged(set.copyWith(targetReps: int.tryParse(value))),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<SetType>(
          value: set.setType,
          items: SetType.values
              .map((type) => DropdownMenuItem(value: type, child: Text(type.name)))
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(set.copyWith(setType: value));
          },
        ),
        IconButton(
          tooltip: 'Remove set',
          icon: const Icon(Icons.close, size: 18),
          onPressed: onRemove,
        ),
      ],
    );
  }
}
