import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../models/exercise.dart';
import '../../models/set_type.dart';
import '../../models/workout.dart';
import '../exercises/exercises_providers.dart';
import 'workouts_providers.dart';
import 'workouts_repository.dart';

/// Create when [workoutId] is null, otherwise edit (and `PUT`-replace) that
/// workout's exercises and sets as a whole.
class WorkoutFormScreen extends ConsumerStatefulWidget {
  const WorkoutFormScreen({super.key, this.workoutId});

  final int? workoutId;

  @override
  ConsumerState<WorkoutFormScreen> createState() => _WorkoutFormScreenState();
}

class _WorkoutFormScreenState extends ConsumerState<WorkoutFormScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<WorkoutExercise> _exercises = [];
  bool _submitting = false;
  String? _error;
  bool _loadedInitialValues = false;

  bool get _isEditing => widget.workoutId != null;

  void _loadFrom(Workout workout) {
    if (_loadedInitialValues) return;
    _loadedInitialValues = true;
    _nameController.text = workout.name;
    _descriptionController.text = workout.description ?? '';
    _exercises = List.of(workout.exercises);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _addExercise(Exercise exercise) {
    setState(() {
      _exercises = [..._exercises, WorkoutExercise(exerciseId: exercise.id!)];
    });
  }

  void _removeExerciseAt(int index) {
    setState(() => _exercises = List.of(_exercises)..removeAt(index));
  }

  void _updateExerciseAt(int index, WorkoutExercise updated) {
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
    final workout = Workout(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      exercises: _exercises,
    );
    final repository = ref.read(workoutsRepositoryProvider);
    try {
      if (_isEditing) {
        await repository.replace(widget.workoutId!, workout);
      } else {
        await repository.create(workout);
      }
      ref.invalidate(workoutListProvider);
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
      await ref.read(workoutsRepositoryProvider).delete(widget.workoutId!);
      ref.invalidate(workoutListProvider);
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
    final title = _isEditing ? 'Edit workout' : 'New workout';
    if (!_isEditing) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _buildForm(context),
      );
    }
    final workoutAsync = ref.watch(workoutProvider(widget.workoutId!));
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Delete workout',
            icon: const Icon(Icons.delete_outline),
            onPressed: _submitting ? null : _delete,
          ),
        ],
      ),
      body: AsyncValueView(
        value: workoutAsync,
        builder: (context, workout) {
          _loadFrom(workout);
          return _buildForm(context);
        },
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
        Text('Exercises', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < _exercises.length; i++)
          _WorkoutExerciseCard(
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
          builder: (context, allExercises) => MenuAnchor(
            builder: (context, controller, child) => OutlinedButton.icon(
              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
            menuChildren: allExercises
                .map(
                  (exercise) => MenuItemButton(
                    onPressed: () => _addExercise(exercise),
                    child: Text(exercise.name),
                  ),
                )
                .toList(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _WorkoutExerciseCard extends StatelessWidget {
  const _WorkoutExerciseCard({
    required this.exercise,
    required this.exerciseName,
    required this.onChanged,
    required this.onRemove,
  });

  final WorkoutExercise exercise;
  final String? exerciseName;
  final ValueChanged<WorkoutExercise> onChanged;
  final VoidCallback onRemove;

  void _addSet() {
    onChanged(exercise.copyWith(sets: [...exercise.sets, const WorkoutSet()]));
  }

  void _removeSetAt(int index) {
    onChanged(exercise.copyWith(sets: List.of(exercise.sets)..removeAt(index)));
  }

  void _updateSetAt(int index, WorkoutSet updated) {
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
  final WorkoutSet set;
  final ValueChanged<WorkoutSet> onChanged;
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
