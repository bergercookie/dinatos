import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/hevy_import_result.dart';
import 'hevy_import_repository.dart';

class HevyImportScreen extends ConsumerStatefulWidget {
  const HevyImportScreen({super.key});

  @override
  ConsumerState<HevyImportScreen> createState() => _HevyImportScreenState();
}

class _HevyImportScreenState extends ConsumerState<HevyImportScreen> {
  bool _importingWorkouts = false;
  bool _importingMeasurements = false;
  HevyWorkoutImportResult? _workoutResult;

  Future<void> _importWorkouts() => _pickAndImport(
    isWorkouts: true,
    setBusy: (value) => setState(() => _importingWorkouts = value),
  );

  Future<void> _importMeasurements() => _pickAndImport(
    isWorkouts: false,
    setBusy: (value) => setState(() => _importingMeasurements = value),
  );

  Future<void> _pickAndImport({
    required bool isWorkouts,
    required void Function(bool busy) setBusy,
  }) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv']);
    if (file == null) return;
    final bytes = await file.readAsBytes();

    setBusy(true);
    try {
      await _upload(isWorkouts: isWorkouts, bytes: bytes, filename: file.name, force: false);
    } on HevyImportAlreadyDoneException catch (error) {
      if (await _confirmForceReimport(error) == true) {
        await _upload(isWorkouts: isWorkouts, bytes: bytes, filename: file.name, force: true);
      }
    } on ApiException catch (error) {
      _showMessage(error.message);
    } finally {
      setBusy(false);
    }
  }

  Future<void> _upload({
    required bool isWorkouts,
    required List<int> bytes,
    required String filename,
    required bool force,
  }) async {
    final repository = ref.read(hevyImportRepositoryProvider);
    if (isWorkouts) {
      final result = await repository.importWorkouts(bytes, filename, force: force);
      if (mounted) setState(() => _workoutResult = result);
      _showMessage(
        'Imported ${result.activitiesCreated} activities '
        '(${result.exercisesCreated} new exercises).',
      );
    } else {
      final result = await repository.importMeasurements(bytes, filename, force: force);
      _showMessage('Imported ${result.measurementsCreated} measurements.');
    }
  }

  Future<bool?> _confirmForceReimport(HevyImportAlreadyDoneException error) {
    final where = [
      if (error.previousFilename != null) 'as "${error.previousFilename}"',
      if (error.previouslyImportedAt != null) 'on ${error.previouslyImportedAt}',
    ].join(' ');
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Already imported'),
        content: Text(
          'A file with this exact content was already imported'
          '${where.isEmpty ? '' : ' $where'}. Import it again anyway?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import again'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from Hevy')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Export your data from Hevy (Settings -> Export), then upload the two CSV files '
              'here. Importing the exact same file twice is safe -- you\'ll be asked to confirm '
              'before it happens.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _importingWorkouts ? null : _importWorkouts,
              icon: _importingWorkouts
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fitness_center),
              label: const Text('Import workouts CSV'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _importingMeasurements ? null : _importMeasurements,
              icon: _importingMeasurements
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.straighten),
              label: const Text('Import measurements CSV'),
            ),
            if (_workoutResult case final result? when result.createdExercises.isNotEmpty) ...[
              const SizedBox(height: 24),
              ImportedExercisesReview(exercises: result.createdExercises),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown once a workouts import has finished and created custom exercises:
/// asks the person to check the equipment/muscles we guessed for them, with
/// a tap-through to each one's edit screen.
class ImportedExercisesReview extends StatelessWidget {
  const ImportedExercisesReview({super.key, required this.exercises});

  final List<ImportedExercise> exercises;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = exercises.length;
    return Card(
      key: const Key('importedExercisesReview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please review $count new custom ${count == 1 ? 'exercise' : 'exercises'}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'These Hevy exercises did not match one of ours exactly, so we created them as '
              'your own. We tried to match their equipment and muscle groups automatically, '
              'but some guesses may be wrong. Tap an exercise to check and edit it.',
            ),
            const SizedBox(height: 8),
            for (final exercise in exercises)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(exercise.name),
                subtitle: Text(_summary(exercise)),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => context.go('/exercises/${exercise.id}/edit'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go('/exercises'),
              icon: const Icon(Icons.list),
              label: const Text('Open exercise list'),
            ),
          ],
        ),
      ),
    );
  }

  static String _summary(ImportedExercise exercise) {
    final equipment = exercise.equipment == null
        ? 'Equipment: not set'
        : 'Equipment: ${exercise.equipment!.label}${exercise.equipmentGuessed ? ' (guessed)' : ''}';
    final muscles = [
      ...exercise.primaryMuscles.map((muscle) => muscle.label),
      ...exercise.secondaryMuscles.map((muscle) => '${muscle.label} (secondary)'),
    ];
    final muscleText = muscles.isEmpty
        ? 'Muscles: not set'
        : 'Muscles: ${muscles.join(', ')}${exercise.musclesGuessed ? ' (guessed)' : ''}';
    return '$equipment\n$muscleText';
  }
}
