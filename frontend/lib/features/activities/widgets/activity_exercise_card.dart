import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/design_tokens.dart';
import '../../../models/activity.dart';
import '../../../models/equipment.dart';
import '../../../models/exercise.dart';
import '../../../models/exercise_history.dart';
import '../../../models/exercise_records.dart';
import '../../../models/set_type.dart';
import '../../../models/uid.dart';
import '../../exercises/exercise_filter_sheet.dart';
import '../../progress/progression.dart';
import 'plate_calculator.dart';

/// One exercise's card within an activity being built up -- its name, its
/// sets so far (weight/reps/set-type), and controls to add/remove either.
/// Shared by [ActivityFormScreen] (a whole activity, built then submitted
/// once) and the live workout screen (sets added one at a time as they're
/// actually performed) -- the editing surface is identical either way.
///
/// The live screen additionally passes [history] (what was done last time,
/// shown as hints and a suggestion for this time) and [records] (so a set
/// that beats the all-time best gets a trophy). Superset and reordering
/// controls appear in the options menu when their callbacks are given.
class ActivityExerciseCard extends StatefulWidget {
  const ActivityExerciseCard({
    super.key,
    required this.exercise,
    required this.catalogExercise,
    required this.onChanged,
    required this.onRemove,
    this.history,
    this.records,
    this.supersetLabel,
    this.onLinkWithNext,
    this.onUnlink,
    this.onMoveUp,
    this.onMoveDown,
    this.onViewProgress,
  });

  final ActivityExercise exercise;

  /// The full catalog `Exercise` this activity exercise points at -- `null`
  /// only while the catalog is still loading. Carries the equipment/muscle
  /// metadata the chips below are built from, not just the name.
  final Exercise? catalogExercise;
  final ValueChanged<ActivityExercise> onChanged;
  final VoidCallback onRemove;

  /// Past sessions of this exercise, newest first; null while unknown (not
  /// loaded yet, or the server couldn't be reached).
  final List<ExerciseHistoryEntry>? history;

  /// This exercise's all-time bests, null while unknown.
  final ExerciseRecords? records;

  /// "A", "B", ... when this exercise is part of a superset.
  final String? supersetLabel;
  final VoidCallback? onLinkWithNext;
  final VoidCallback? onUnlink;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onViewProgress;

  @override
  State<ActivityExerciseCard> createState() => _ActivityExerciseCardState();
}

enum _ExerciseAction { linkWithNext, unlink, moveUp, moveDown, viewProgress, toggleNotes }

class _ActivityExerciseCardState extends State<ActivityExerciseCard> {
  late bool _showNotes = (widget.exercise.notes ?? '').isNotEmpty;

  ActivityExercise get _exercise => widget.exercise;

  void _addSet() {
    widget.onChanged(
      _exercise.copyWith(
        sets: [
          ..._exercise.sets,
          ActivitySet(uid: nextUid(), completed: false),
        ],
      ),
    );
  }

  List<SetRecord> _recordFlags(ExerciseRecords records) {
    final done = detectSetRecords([..._exercise.completedSets], records);
    var next = 0;
    return [for (final set in _exercise.sets) set.completed ? done[next++] : const SetRecord()];
  }

  void _removeSetAt(int index) {
    widget.onChanged(_exercise.copyWith(sets: List.of(_exercise.sets)..removeAt(index)));
  }

  void _updateSetAt(int index, ActivitySet updated) {
    widget.onChanged(_exercise.copyWith(sets: List.of(_exercise.sets)..[index] = updated));
  }

  void _applySuggestion(OverloadSuggestion suggestion) {
    widget.onChanged(
      _exercise.copyWith(
        sets: applySuggestion(
          _exercise.sets,
          suggestion,
          newSet: () => ActivitySet(uid: nextUid(), completed: false),
        ),
      ),
    );
  }

  void _onAction(_ExerciseAction action) {
    switch (action) {
      case _ExerciseAction.linkWithNext:
        widget.onLinkWithNext?.call();
      case _ExerciseAction.unlink:
        widget.onUnlink?.call();
      case _ExerciseAction.moveUp:
        widget.onMoveUp?.call();
      case _ExerciseAction.moveDown:
        widget.onMoveDown?.call();
      case _ExerciseAction.viewProgress:
        widget.onViewProgress?.call();
      case _ExerciseAction.toggleNotes:
        setState(() => _showNotes = !_showNotes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catalog = widget.catalogExercise;
    final history = widget.history;
    final last = history == null || history.isEmpty ? null : history.first;
    final suggestion = suggestOverload(last);
    final records = widget.records;
    // Only ticked-off sets can set a record, and only they raise the bar for
    // the sets after them.
    final recordFlags = records == null ? const <SetRecord>[] : _recordFlags(records);
    final inSuperset = widget.supersetLabel != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      // A superset's members are outlined, so the run reads as one block.
      shape: inSuperset
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    catalog?.name ?? '#${_exercise.exerciseId}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (inSuperset)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      label: Text('Superset ${widget.supersetLabel}'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: scheme.primaryContainer,
                      labelStyle: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12),
                      side: BorderSide.none,
                    ),
                  ),
                PopupMenuButton<_ExerciseAction>(
                  tooltip: 'Exercise options',
                  onSelected: _onAction,
                  itemBuilder: (context) => [
                    if (widget.onLinkWithNext != null)
                      const PopupMenuItem(
                        value: _ExerciseAction.linkWithNext,
                        child: Text('Superset with next exercise'),
                      ),
                    if (inSuperset && widget.onUnlink != null)
                      const PopupMenuItem(
                        value: _ExerciseAction.unlink,
                        child: Text('Remove from superset'),
                      ),
                    if (widget.onMoveUp != null)
                      const PopupMenuItem(value: _ExerciseAction.moveUp, child: Text('Move up')),
                    if (widget.onMoveDown != null)
                      const PopupMenuItem(
                        value: _ExerciseAction.moveDown,
                        child: Text('Move down'),
                      ),
                    if (widget.onViewProgress != null)
                      const PopupMenuItem(
                        value: _ExerciseAction.viewProgress,
                        child: Text('View progress'),
                      ),
                    PopupMenuItem(
                      value: _ExerciseAction.toggleNotes,
                      child: Text(_showNotes ? 'Hide note' : 'Add note'),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Remove exercise',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            if (catalog != null) _ExerciseMetadataChips(exercise: catalog),
            if (last != null)
              _LastTimePanel(last: last, suggestion: suggestion, onUse: _applySuggestion),
            if (_showNotes)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: TextFormField(
                  initialValue: _exercise.notes,
                  decoration: const InputDecoration(labelText: 'Note', isDense: true),
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 3,
                  onChanged: (value) =>
                      widget.onChanged(_exercise.copyWith(notes: value.isEmpty ? null : value)),
                ),
              ),
            for (var i = 0; i < _exercise.sets.length; i++)
              ActivitySetRow(
                key: ValueKey(
                  itemKeyOf(uid: _exercise.sets[i].uid, id: _exercise.sets[i].id, index: i),
                ),
                index: i,
                set: _exercise.sets[i],
                previous: last != null && i < last.sets.length ? last.sets[i] : null,
                record: i < recordFlags.length ? recordFlags[i] : null,
                weightEnabled: catalog?.equipment != Equipment.bodyOnly,
                // Until the catalog loads, show the defaults (weight x reps).
                showWeight: catalog?.tracksWeight ?? true,
                showReps: catalog?.tracksReps ?? true,
                showDistance: catalog?.tracksDistance ?? false,
                showDuration: catalog?.tracksDuration ?? false,
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

/// What was done last time, and (if there is one) what to try now with a
/// button to fill it into the sets.
class _LastTimePanel extends StatelessWidget {
  const _LastTimePanel({required this.last, required this.suggestion, required this.onUse});

  final ExerciseHistoryEntry last;
  final OverloadSuggestion? suggestion;
  final ValueChanged<OverloadSuggestion> onUse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = describeSets(last.sets);
    final suggestion = this.suggestion;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last time · ${DateFormat.MMMd().format(last.startedAt.toLocal())}'
                  '${summary.isEmpty ? '' : ': $summary'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (suggestion != null)
                  Text(
                    suggestion.advice,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          if (suggestion != null)
            TextButton(
              onPressed: () => onUse(suggestion),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Use'),
            ),
        ],
      ),
    );
  }
}

/// The equipment and muscle chips under an activity exercise's title --
/// each one tappable, opening a sheet of every other exercise that uses
/// that equipment or trains that muscle (see `ExerciseFilterSheet`), so a
/// chip answers "what else works this" rather than merely labeling the
/// exercise it's on.
class _ExerciseMetadataChips extends StatelessWidget {
  const _ExerciseMetadataChips({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final equipment = exercise.equipment;
    if (equipment == null && exercise.primaryMuscles.isEmpty && exercise.secondaryMuscles.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (equipment != null)
            _MetadataChip(
              label: equipment.label,
              onTap: () => ExerciseFilterSheet.showForEquipment(context, equipment),
            ),
          for (final muscle in exercise.primaryMuscles)
            _MetadataChip(
              label: muscle.label,
              onTap: () => ExerciseFilterSheet.showForMuscle(context, muscle),
            ),
          for (final muscle in exercise.secondaryMuscles)
            _MetadataChip(
              label: muscle.label,
              muted: true,
              onTap: () => ExerciseFilterSheet.showForMuscle(context, muscle),
            ),
        ],
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label, required this.onTap, this.muted = false});

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      labelStyle: muted ? TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
      onPressed: onTap,
    );
  }
}

enum _SetAction { plateCalculator, remove }

Color _doneGreen(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? Colors.green.shade400 : Colors.green.shade600;

/// The tint of a completed set's row: clearly green in both themes, light
/// enough to keep the numbers readable.
Color _completedGreen(BuildContext context) => _doneGreen(context).withValues(alpha: 0.2);

class ActivitySetRow extends StatelessWidget {
  const ActivitySetRow({
    super.key,
    required this.index,
    required this.set,
    required this.onChanged,
    required this.onRemove,
    this.weightEnabled = true,
    this.previous,
    this.record,
    this.showWeight = true,
    this.showReps = true,
    this.showDistance = false,
    this.showDuration = false,
  });

  final int index;
  final ActivitySet set;

  /// Which measurements the exercise tracks (see `Exercise.tracks*`); only
  /// those get a field.
  final bool showWeight;
  final bool showReps;
  final bool showDistance;
  final bool showDuration;

  /// The same-numbered set from the last session, shown as the fields' hints.
  final ActivitySet? previous;

  /// Which records this set set, if known; a trophy marks one.
  final SetRecord? record;

  /// `false` for a body-weight exercise: there is no load to enter.
  final bool weightEnabled;
  final ValueChanged<ActivitySet> onChanged;
  final VoidCallback onRemove;

  static String? _hint(num? value) => value == null ? null : formatKg(value.toDouble());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final record = this.record;
    final previous = this.previous;
    final floating = previous == null ? null : FloatingLabelBehavior.always;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        // A distinct green once the set is ticked off as done.
        color: set.completed ? _completedGreen(context) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${index + 1}.'),
                // Tapping steps warm-up > normal > drop set > failure > ...
                Tooltip(
                  message: '${set.setType.name} set -- tap to change',
                  child: Semantics(
                    button: true,
                    label: 'Set type: ${set.setType.name}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () => onChanged(set.copyWith(setType: set.setType.next)),
                      child: Container(
                        width: 28,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          color: set.setType == SetType.normal
                              ? scheme.surfaceContainerHighest
                              : scheme.primaryContainer,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          set.setType.letter,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: set.setType == SetType.normal
                                ? scheme.onSurfaceVariant
                                : scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (record != null && record.any && set.completed)
                  Tooltip(
                    message: 'New personal record',
                    child: Icon(Icons.emoji_events, size: 16, color: scheme.tertiary),
                  ),
              ],
            ),
          ),
          if (showWeight) ...[
            Expanded(
              flex: 3,
              child: _NumberField(
                value: set.weightKg,
                label: 'kg',
                hint: _hint(previous?.weightKg),
                floating: floating,
                enabled: weightEnabled,
                decimal: true,
                onChanged: (value) => onChanged(set.copyWith(weightKg: value)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (showReps) ...[
            Expanded(
              flex: 3,
              child: _NumberField(
                value: set.reps?.toDouble(),
                label: 'reps',
                hint: _hint(previous?.reps),
                floating: floating,
                decimal: false,
                onChanged: (value) => onChanged(set.copyWith(reps: value?.round())),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (showDistance) ...[
            Expanded(
              flex: 3,
              child: _NumberField(
                value: set.distanceKm,
                label: 'km',
                hint: _hint(previous?.distanceKm),
                floating: floating,
                decimal: true,
                onChanged: (value) => onChanged(set.copyWith(distanceKm: value)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (showDuration) ...[
            Expanded(
              flex: 3,
              child: _NumberField(
                value: set.durationSeconds?.toDouble(),
                label: 'sec',
                hint: _hint(previous?.durationSeconds),
                floating: floating,
                decimal: false,
                onChanged: (value) => onChanged(set.copyWith(durationSeconds: value?.round())),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: set.completed ? 'Done -- tap to undo' : 'Mark set as done',
            child: Checkbox(
              key: const ValueKey('set-done'),
              value: set.completed,
              activeColor: _doneGreen(context),
              visualDensity: VisualDensity.compact,
              semanticLabel: set.completed ? 'Set done' : 'Mark set as done',
              onChanged: (value) => onChanged(set.copyWith(completed: value ?? false)),
            ),
          ),
          PopupMenuButton<Object>(
            tooltip: 'Set options',
            onSelected: (value) {
              if (value == _SetAction.plateCalculator) {
                showPlateCalculator(context, targetKg: set.weightKg);
              } else if (value == _SetAction.remove) {
                onRemove();
              }
            },
            itemBuilder: (context) => [
              if (weightEnabled)
                const PopupMenuItem<Object>(
                  value: _SetAction.plateCalculator,
                  child: Text('Plate calculator'),
                ),
              const PopupMenuItem<Object>(value: _SetAction.remove, child: Text('Remove set')),
            ],
          ),
        ],
      ),
    );
  }
}

/// A numeric text field bound to [value]: edits are parsed and reported
/// through [onChanged] (null for an empty or unparseable field), and a change
/// to [value] from outside -- a suggestion filled in -- is shown, which a
/// plain `initialValue` would not.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.value,
    required this.label,
    required this.onChanged,
    required this.decimal,
    this.hint,
    this.floating,
    this.enabled = true,
  });

  final double? value;
  final String label;
  final String? hint;
  final FloatingLabelBehavior? floating;
  final bool enabled;
  final bool decimal;
  final ValueChanged<double?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(text: _format(widget.value));

  static String _format(double? value) => value == null ? '' : formatKg(value);

  /// What the model holds for [text]: the number it spells, or null if it is
  /// empty or unparseable.
  double? _modelValueOf(String text) =>
      widget.decimal ? double.tryParse(text) : int.tryParse(text)?.toDouble();

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    // Only when the model moved away from what the field already says; while
    // typing, the model follows the field, so this never fights the keyboard.
    if (widget.value != _modelValueOf(_controller.text)) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        floatingLabelBehavior: widget.floating,
        isDense: true,
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(widget.decimal ? r'[0-9.]' : r'[0-9]')),
      ],
      onChanged: (text) => widget.onChanged(_modelValueOf(text)),
    );
  }
}
