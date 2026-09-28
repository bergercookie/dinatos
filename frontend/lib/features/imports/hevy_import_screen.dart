import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import 'hevy_import_repository.dart';

class HevyImportScreen extends ConsumerStatefulWidget {
  const HevyImportScreen({super.key});

  @override
  ConsumerState<HevyImportScreen> createState() => _HevyImportScreenState();
}

class _HevyImportScreenState extends ConsumerState<HevyImportScreen> {
  bool _importingWorkouts = false;
  bool _importingMeasurements = false;

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
      body: ListView(
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
        ],
      ),
    );
  }
}
