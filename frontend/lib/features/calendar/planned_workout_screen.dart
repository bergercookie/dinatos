import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/planned_workout.dart';
import '../routines/routines_providers.dart';
import 'planned_workouts_providers.dart';
import 'planned_workouts_repository.dart';

/// The reminder choices: minutes before the start, or null for none.
const reminderChoices = <int?, String>{
  null: 'No reminder',
  0: 'When it starts',
  10: '10 minutes before',
  30: '30 minutes before',
  60: '1 hour before',
  120: '2 hours before',
  1440: '1 day before',
};

const durationChoices = <int>[30, 45, 60, 75, 90, 120, 180];

/// Schedules a workout (when [plannedId] is null), or edits that planned workout.
/// [initialDate] pre-fills the day when it was started from a calendar cell.
class PlannedWorkoutScreen extends ConsumerWidget {
  const PlannedWorkoutScreen({super.key, this.plannedId, this.initialDate});

  final int? plannedId;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = plannedId;
    if (id == null) return _PlannedWorkoutForm(initialDate: initialDate);
    final plan = ref.watch(plannedWorkoutProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Planned workout')),
      body: AsyncValueView(
        value: plan,
        onRetry: () => ref.invalidate(plannedWorkoutProvider(id)),
        builder: (context, data) => _PlannedWorkoutForm(existing: data),
      ),
    );
  }
}

class _PlannedWorkoutForm extends ConsumerStatefulWidget {
  const _PlannedWorkoutForm({this.existing, this.initialDate});

  final PlannedWorkout? existing;
  final DateTime? initialDate;

  @override
  ConsumerState<_PlannedWorkoutForm> createState() => _PlannedWorkoutFormState();
}

class _PlannedWorkoutFormState extends ConsumerState<_PlannedWorkoutForm> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _date;
  late TimeOfDay _time;
  int? _routineId;
  int _duration = 60;
  int? _reminder = 30;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _title.text = existing.title;
      _notes.text = existing.notes ?? '';
      _date = DateTime(
        existing.scheduledAt.year,
        existing.scheduledAt.month,
        existing.scheduledAt.day,
      );
      _time = TimeOfDay.fromDateTime(existing.scheduledAt);
      _routineId = existing.routineId;
      _duration = existing.durationMinutes;
      _reminder = existing.reminderMinutes;
    } else {
      final base = widget.initialDate ?? DateTime.now().add(const Duration(days: 1));
      _date = DateTime(base.year, base.month, base.day);
      _time = const TimeOfDay(hour: 18, minute: 0);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _scheduledAt =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year, today.month, today.day).isBefore(_date)
          ? DateTime(today.year, today.month, today.day)
          : _date,
      lastDate: DateTime(today.year + 3),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty && _routineId == null) {
      setState(() => _error = 'Give it a title, or pick a routine.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final routines = ref.read(routineListProvider).valueOrNull ?? const [];
    final routineName = routines.where((r) => r.id == _routineId).map((r) => r.name).firstOrNull;
    final notes = _notes.text.trim();
    final plan = PlannedWorkout(
      title: title.isEmpty ? (routineName ?? '') : title,
      notes: notes.isEmpty ? null : notes,
      scheduledAt: _scheduledAt,
      routineId: _routineId,
      durationMinutes: _duration,
      reminderMinutes: _reminder,
    );
    try {
      final repository = ref.read(plannedWorkoutsRepositoryProvider);
      final id = widget.existing?.id;
      if (id == null) {
        await repository.create(plan);
      } else {
        await repository.replace(id, plan);
        ref.invalidate(plannedWorkoutProvider(id));
      }
      ref.invalidate(plannedWorkoutListProvider);
      if (mounted) _leave();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error.message;
        });
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from calendar?'),
        content: Text('"${widget.existing!.title}" will no longer be planned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(plannedWorkoutsRepositoryProvider).delete(id);
      ref.invalidate(plannedWorkoutListProvider);
      if (mounted) _leave();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/activities');
    }
  }

  @override
  Widget build(BuildContext context) {
    final routines = ref.watch(routineListProvider);
    final editing = widget.existing != null;
    final dateText = DateFormat.yMMMEd().format(_date);
    final timeText = _time.format(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Planned workout' : 'Schedule workout'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Remove from calendar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _submitting ? null : _delete,
            ),
        ],
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.md),
            ],
            routines.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Could not load your routines.'),
              data: (data) => DropdownButtonFormField<int?>(
                initialValue: data.any((r) => r.id == _routineId) ? _routineId : null,
                decoration: const InputDecoration(labelText: 'Routine'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('None (from scratch)')),
                  for (final routine in data)
                    DropdownMenuItem<int?>(value: routine.id, child: Text(routine.name)),
                ],
                onChanged: (value) => setState(() => _routineId = value),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                helperText: 'Optional when a routine is picked -- its name is used.',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event),
                    label: Text(dateText),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(timeText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<int>(
              initialValue: _duration,
              decoration: const InputDecoration(labelText: 'Duration'),
              items: [
                for (final minutes in {...durationChoices, _duration}.toList()..sort())
                  DropdownMenuItem(value: minutes, child: Text('$minutes minutes')),
              ],
              onChanged: (value) => setState(() => _duration = value ?? _duration),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<int?>(
              initialValue: reminderChoices.containsKey(_reminder) ? _reminder : null,
              decoration: const InputDecoration(
                labelText: 'Reminder',
                helperText: 'A notification on this device, tap it to start the workout.',
              ),
              items: [
                for (final entry in reminderChoices.entries)
                  DropdownMenuItem<int?>(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => setState(() => _reminder = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _submitting ? null : _save,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(editing ? 'Save changes' : 'Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
