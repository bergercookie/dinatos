import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/design_tokens.dart';
import '../../core/file_io.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/data_transfer_result.dart';
import '../activities/activities_providers.dart';
import '../exercises/exercises_providers.dart';
import '../measurements/measurements_providers.dart';
import '../routines/routines_providers.dart';
import 'profile_providers.dart';
import 'profile_repository.dart';

/// Everything that brings data into the account or takes a copy out of it,
/// in one place: the Hevy and Intervals.icu importers, and the export and
/// re-import of the account's own data file. Reached from one tile on the
/// Settings screen (`/profile/import-export`); the importers are sub-routes,
/// so their back button returns here.
///
/// The server-wide backup and restore is *not* here: it is admin-only and
/// lives under Administration.
class ImportExportScreen extends ConsumerStatefulWidget {
  const ImportExportScreen({super.key});

  @override
  ConsumerState<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  Future<void> _exportData() async {
    try {
      final file = await ref.read(profileRepositoryProvider).exportMyData();
      final saved = await ref.read(fileSaverProvider)(file);
      if (saved) _showMessage('Your data was saved as ${file.name}.');
    } on ApiException catch (error) {
      _showMessage('Export failed: ${error.message}');
    }
  }

  Future<void> _importData() async {
    final file = await ref.read(jsonFilePickerProvider)();
    if (file == null || !mounted) return;
    final mode = await showDialog<UserImportMode>(
      context: context,
      builder: (context) => _ImportModeDialog(fileName: file.name),
    );
    if (mode == null) return;
    try {
      final result = await ref.read(profileRepositoryProvider).importMyData(file, mode);
      ref.invalidate(profileProvider);
      ref.invalidate(routineListProvider);
      ref.invalidate(activityListProvider);
      ref.invalidate(measurementListProvider);
      ref.invalidate(exerciseListProvider);
      ref.invalidate(exercisePagingProvider);
      _showMessage(result.summary());
    } on ApiException catch (error) {
      _showMessage('Import failed, nothing was changed: ${error.message}');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import and export'),
        leading: BackButton(onPressed: () => context.go('/profile')),
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const _SectionHeader('Import'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: const Text('Import from Hevy'),
                    subtitle: const Text('Upload your Hevy workout/measurement CSV exports'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/profile/import-export/hevy'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sync_alt_outlined),
                    title: const Text('Import from Intervals.icu'),
                    subtitle: const Text('Choose which Intervals.icu activities to bring over'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/profile/import-export/intervals'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('Import my data'),
                    subtitle: const Text('Load a file you exported from Dinatos'),
                    onTap: _importData,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SectionHeader('Export'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export my data'),
                subtitle: const Text(
                  'Save your settings, routines, activities and measurements as a file',
                ),
                onTap: _exportData,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Pops the chosen [UserImportMode], or null if cancelled. Replace is the
/// destructive one and says exactly what it deletes.
class _ImportModeDialog extends StatefulWidget {
  const _ImportModeDialog({required this.fileName});

  final String fileName;

  @override
  State<_ImportModeDialog> createState() => _ImportModeDialogState();
}

class _ImportModeDialogState extends State<_ImportModeDialog> {
  UserImportMode _mode = UserImportMode.merge;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import my data'),
      content: SingleChildScrollView(
        child: RadioGroup<UserImportMode>(
          groupValue: _mode,
          onChanged: (value) => setState(() => _mode = value ?? _mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From "${widget.fileName}".'),
              const SizedBox(height: AppSpacing.md),
              const RadioListTile<UserImportMode>(
                value: UserImportMode.merge,
                title: Text('Merge'),
                subtitle: Text(
                  'Keep what you have and add what is missing. Routines with the same name, '
                  'and activities or measurements at the same time, are skipped.',
                ),
              ),
              const RadioListTile<UserImportMode>(
                value: UserImportMode.replace,
                title: Text('Replace my data'),
                subtitle: Text(
                  'First deletes ALL your routines, activities and measurements, then imports '
                  'the file.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _mode),
          child: Text(_mode == UserImportMode.replace ? 'Replace and import' : 'Import'),
        ),
      ],
    );
  }
}
