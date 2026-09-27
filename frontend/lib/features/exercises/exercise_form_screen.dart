import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../models/exercise.dart';
import 'exercises_providers.dart';
import 'exercises_repository.dart';

/// Create when [exerciseId] is null, otherwise edit that exercise in place.
class ExerciseFormScreen extends ConsumerStatefulWidget {
  const ExerciseFormScreen({super.key, this.exerciseId});

  final int? exerciseId;

  @override
  ConsumerState<ExerciseFormScreen> createState() => _ExerciseFormScreenState();
}

class _ExerciseFormScreenState extends ConsumerState<ExerciseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _tracksWeight = true;
  bool _tracksReps = true;
  bool _tracksDistance = false;
  bool _tracksDuration = false;
  bool _submitting = false;
  String? _error;
  bool _loadedInitialValues = false;

  bool get _isEditing => widget.exerciseId != null;

  void _loadFrom(Exercise exercise) {
    if (_loadedInitialValues) return;
    _loadedInitialValues = true;
    _nameController.text = exercise.name;
    _tracksWeight = exercise.tracksWeight;
    _tracksReps = exercise.tracksReps;
    _tracksDistance = exercise.tracksDistance;
    _tracksDuration = exercise.tracksDuration;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final exercise = Exercise(
      name: _nameController.text.trim(),
      tracksWeight: _tracksWeight,
      tracksReps: _tracksReps,
      tracksDistance: _tracksDistance,
      tracksDuration: _tracksDuration,
    );
    final repository = ref.read(exercisesRepositoryProvider);
    try {
      if (_isEditing) {
        await repository.update(widget.exerciseId!, exercise);
      } else {
        await repository.create(exercise);
      }
      ref.invalidate(exerciseListProvider);
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
      await ref.read(exercisesRepositoryProvider).delete(widget.exerciseId!);
      ref.invalidate(exerciseListProvider);
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
    final title = _isEditing ? 'Edit exercise' : 'New exercise';
    if (!_isEditing) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _buildForm(context),
      );
    }
    final exerciseAsync = ref.watch(exerciseProvider(widget.exerciseId!));
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Delete exercise',
            icon: const Icon(Icons.delete_outline),
            onPressed: _submitting ? null : _delete,
          ),
        ],
      ),
      body: AsyncValueView(
        value: exerciseAsync,
        builder: (context, exercise) {
          _loadFrom(exercise);
          return _buildForm(context);
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (value) => (value == null || value.isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 16),
          Text('Tracks', style: Theme.of(context).textTheme.titleMedium),
          CheckboxListTile(
            title: const Text('Weight'),
            value: _tracksWeight,
            onChanged: (value) => setState(() => _tracksWeight = value ?? false),
          ),
          CheckboxListTile(
            title: const Text('Reps'),
            value: _tracksReps,
            onChanged: (value) => setState(() => _tracksReps = value ?? false),
          ),
          CheckboxListTile(
            title: const Text('Distance'),
            value: _tracksDistance,
            onChanged: (value) => setState(() => _tracksDistance = value ?? false),
          ),
          CheckboxListTile(
            title: const Text('Duration'),
            value: _tracksDuration,
            onChanged: (value) => setState(() => _tracksDuration = value ?? false),
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
      ),
    );
  }
}
