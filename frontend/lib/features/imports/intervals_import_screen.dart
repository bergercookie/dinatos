import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_exception.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/intervals_import.dart';
import 'intervals_import_repository.dart';

/// One-time import of Intervals.icu activities: enter the API key and a date
/// range, fetch the list, tick what to bring over, import. The key is sent
/// to the backend for each of those two requests and never stored.
class IntervalsImportScreen extends ConsumerStatefulWidget {
  const IntervalsImportScreen({super.key});

  @override
  ConsumerState<IntervalsImportScreen> createState() => _IntervalsImportScreenState();
}

class _IntervalsImportScreenState extends ConsumerState<IntervalsImportScreen> {
  final _apiKey = TextEditingController();
  final _athleteId = TextEditingController(text: '0');
  late DateTime _oldest = _today().subtract(const Duration(days: 90));
  late final DateTime _newest = _today();

  bool _busy = false;
  String? _error;

  // The window and key the list below was fetched with -- the import
  // re-reads the same window, so a field edited since must not leak in.
  List<IntervalsActivity>? _activities;
  final Set<String> _selected = {};
  ({String athleteId, String apiKey, DateTime oldest, DateTime newest})? _fetched;
  IntervalsImportResult? _result;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _athleteId.dispose();
    super.dispose();
  }

  Future<void> _pickOldest() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _oldest,
      firstDate: DateTime(2000),
      lastDate: _newest,
    );
    if (picked != null) setState(() => _oldest = picked);
  }

  Future<void> _fetch() async {
    final apiKey = _apiKey.text.trim();
    final athleteId = _athleteId.text.trim().isEmpty ? '0' : _athleteId.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _error = 'Enter your Intervals.icu API key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final activities = await ref
          .read(intervalsImportRepositoryProvider)
          .preview(athleteId: athleteId, apiKey: apiKey, oldest: _oldest, newest: _newest);
      if (!mounted) return;
      setState(() {
        _activities = activities;
        _fetched = (athleteId: athleteId, apiKey: apiKey, oldest: _oldest, newest: _newest);
        _selected
          ..clear()
          ..addAll(activities.where((a) => a.selectedByDefault).map((a) => a.id));
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import({bool force = false}) async {
    final source = _fetched!;
    final ids = _activities!.where((a) => _selected.contains(a.id)).map((a) => a.id).toList();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(intervalsImportRepositoryProvider)
          .import(
            athleteId: source.athleteId,
            apiKey: source.apiKey,
            oldest: source.oldest,
            newest: source.newest,
            activityIds: ids,
            force: force,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _activities = null;
        _fetched = null;
        _selected.clear();
      });
    } on IntervalsAlreadyImportedException {
      // Not busy while the question is up; a "yes" starts the forced import itself.
      if (mounted) setState(() => _busy = false);
      if (mounted && await _confirmForce() == true) {
        await _import(force: true);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmForce() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Already imported'),
      content: const Text(
        'Some of the selected activities were already imported from Intervals.icu. '
        'Import them again anyway? That creates a second copy of each.',
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

  @override
  Widget build(BuildContext context) {
    final activities = _activities;
    return Scaffold(
      appBar: AppBar(title: const Text('Import from Intervals.icu')),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'A one-time import of activities from Intervals.icu. Fetch your activities for a '
              'date range, then tick the ones to import -- anything already in Dinatos (including '
              'workouts synced from Hevy) is left unticked. An activity that was imported before '
              'is never imported twice unless you confirm it. Your API key is only used for '
              'these requests and is not stored. Find it in Intervals.icu under Settings -> '
              'Developer Settings.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKey,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'API key'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _athleteId,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Athlete ID',
                helperText: '0 means the owner of the API key',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickOldest,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('From ${DateFormat.yMMMd().format(_oldest)}'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _fetch,
              icon: const Icon(Icons.cloud_download_outlined),
              label: Text(activities == null ? 'Fetch activities' : 'Fetch again'),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const Key('intervalsError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_result case final result?) _ResultCard(result: result),
            if (activities != null) ...[const SizedBox(height: 16), _selection(activities)],
          ],
        ),
      ),
    );
  }

  Widget _selection(List<IntervalsActivity> activities) {
    if (activities.isEmpty) {
      return const Text('No activities in that date range.');
    }
    final selectable = activities.where((a) => a.importable).map((a) => a.id).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('${_selected.length} of ${selectable.length} selected')),
            TextButton(
              onPressed: () => setState(() => _selected.addAll(selectable)),
              child: const Text('All'),
            ),
            TextButton(onPressed: () => setState(_selected.clear), child: const Text('None')),
          ],
        ),
        for (final activity in activities)
          CheckboxListTile(
            key: Key('intervals-${activity.id}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _selected.contains(activity.id),
            onChanged: activity.importable
                ? (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(activity.id);
                    } else {
                      _selected.remove(activity.id);
                    }
                  })
                : null,
            title: Text(activity.name),
            subtitle: Text(_describe(activity)),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy || _selected.isEmpty ? null : _import,
          icon: const Icon(Icons.file_download_done_outlined),
          label: Text(
            'Import ${_selected.length} ${_selected.length == 1 ? 'activity' : 'activities'}',
          ),
        ),
      ],
    );
  }

  static String _describe(IntervalsActivity activity) {
    if (!activity.importable) {
      return 'Can\'t be imported: ${activity.unimportableReason ?? 'unavailable'}';
    }
    final parts = [
      if (activity.startedAt != null) DateFormat.yMMMd().add_Hm().format(activity.startedAt!),
      if (activity.type != null) activity.type!,
      if (activity.durationSeconds != null) _duration(activity.durationSeconds!),
      if (activity.distanceKm != null) '${activity.distanceKm!.toStringAsFixed(1)} km',
    ];
    final notes = [
      if (activity.alreadyImported) 'Already imported',
      if (activity.possibleDuplicateOf != null)
        'Possible duplicate of "${activity.possibleDuplicateOf}"',
    ];
    return [parts.join(' · '), ...notes].join('\n');
  }

  static String _duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final IntervalsImportResult result;

  @override
  Widget build(BuildContext context) {
    final count = result.activitiesCreated;
    return Card(
      key: const Key('intervalsResult'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Imported $count ${count == 1 ? 'activity' : 'activities'}'
              '${result.exercisesCreated > 0 ? ' (${result.exercisesCreated} new exercises)' : ''}.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go('/activities'),
              icon: const Icon(Icons.history),
              label: const Text('Open activities'),
            ),
          ],
        ),
      ),
    );
  }
}
