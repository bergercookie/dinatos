import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/info_banner.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/exercise.dart';
import 'exercises_providers.dart';
import 'exercises_repository.dart';

/// Create when [exerciseId] is null, otherwise edit that exercise in place --
/// or, if it turns out to be a built-in exercise, show it read-only.
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
  bool _isCustom = true;
  bool _submitting = false;
  String? _error;
  bool _loadedInitialValues = false;

  bool get _isEditing => widget.exerciseId != null;

  /// A built-in exercise that's already loaded is read-only -- everything
  /// else (a new exercise, or one that turns out to be custom) is editable.
  bool get _isReadOnly => _isEditing && _loadedInitialValues && !_isCustom;

  void _loadFrom(Exercise exercise) {
    if (_loadedInitialValues) return;
    _loadedInitialValues = true;
    _nameController.text = exercise.name;
    _tracksWeight = exercise.tracksWeight;
    _tracksReps = exercise.tracksReps;
    _tracksDistance = exercise.tracksDistance;
    _tracksDuration = exercise.tracksDuration;
    _isCustom = exercise.isCustom;
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
      ref.invalidate(exercisePagingProvider);
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
      ref.invalidate(exercisePagingProvider);
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
        body: ResponsiveBody(child: _buildForm(context)),
      );
    }
    final exerciseAsync = ref.watch(exerciseProvider(widget.exerciseId!));
    // Hidden, not just disabled, until the exercise has loaded and turns out
    // to be custom -- a built-in exercise should never offer a delete
    // action at all (see `Exercise.isCustom`'s doc).
    final canDelete = exerciseAsync.valueOrNull?.isCustom ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (canDelete)
            IconButton(
              tooltip: 'Delete exercise',
              icon: const Icon(Icons.delete_outline),
              onPressed: _submitting ? null : _delete,
            ),
        ],
      ),
      body: ResponsiveBody(
        child: AsyncValueView(
          value: exerciseAsync,
          builder: (context, exercise) {
            _loadFrom(exercise);
            return _buildForm(context);
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final readOnly = _isReadOnly;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (readOnly) ...[
            const InfoBanner(
              message:
                  'This is a built-in exercise and cannot be edited or deleted. '
                  'Add a custom exercise instead if you need something different.',
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            enabled: !readOnly,
            validator: (value) => (value == null || value.isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 16),
          Text('Tracks', style: Theme.of(context).textTheme.titleMedium),
          CheckboxListTile(
            title: const Text('Weight'),
            value: _tracksWeight,
            onChanged: readOnly ? null : (value) => setState(() => _tracksWeight = value ?? false),
          ),
          CheckboxListTile(
            title: const Text('Reps'),
            value: _tracksReps,
            onChanged: readOnly ? null : (value) => setState(() => _tracksReps = value ?? false),
          ),
          CheckboxListTile(
            title: const Text('Distance'),
            value: _tracksDistance,
            onChanged: readOnly
                ? null
                : (value) => setState(() => _tracksDistance = value ?? false),
          ),
          CheckboxListTile(
            title: const Text('Duration'),
            value: _tracksDuration,
            onChanged: readOnly
                ? null
                : (value) => setState(() => _tracksDuration = value ?? false),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          if (!readOnly) ...[
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_isEditing ? 'Save' : 'Create'),
            ),
          ],
        ],
      ),
    );
  }
}
