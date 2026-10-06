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
/// sets so far (weight/reps/RPE/set-type), and controls to add/remove either.
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
          ActivitySet(uid: nextUid()),
        ],
      ),
    );
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
          newSet: () => ActivitySet(uid: nextUid()),
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
    final recordFlags = records == null
        ? const <SetRecord>[]
        : detectSetRecords(_exercise.sets, records);
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${index + 1}.'),
                if (set.setType != SetType.normal)
                  Tooltip(
                    message: set.setType.name,
                    child: Text(
                      set.setType.name[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                if (record != null && record.any)
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
          Expanded(
            flex: 2,
            child: _NumberField(
              value: set.rpe,
              label: 'RPE',
              hint: _hint(previous?.rpe),
              floating: floating,
              decimal: true,
              // 1-10, in halves; anything else is a typo, not an effort.
              validator: (value) => value < 1 || value > 10 ? '1–10' : null,
              onChanged: (value) => onChanged(set.copyWith(rpe: value)),
            ),
          ),
          PopupMenuButton<Object>(
            tooltip: 'Set options',
            onSelected: (value) {
              if (value is SetType) {
                onChanged(set.copyWith(setType: value));
              } else if (value == _SetAction.plateCalculator) {
                showPlateCalculator(context, targetKg: set.weightKg);
              } else if (value == _SetAction.remove) {
                onRemove();
              }
            },
            itemBuilder: (context) => [
              for (final type in SetType.values)
                CheckedPopupMenuItem<Object>(
                  value: type,
                  checked: type == set.setType,
                  child: Text(type.name),
                ),
              const PopupMenuDivider(),
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
    this.validator,
  });

  final double? value;
  final String label;
  final String? hint;
  final FloatingLabelBehavior? floating;
  final bool enabled;
  final bool decimal;

  /// An error message for an entered value that is out of range, or null.
  final String? Function(double value)? validator;
  final ValueChanged<double?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(text: _format(widget.value));

  static String _format(double? value) => value == null ? '' : formatKg(value);

  /// What the model holds for [text]: the number it spells, or null if it is
  /// empty, unparseable or rejected by the validator (flagged, not recorded).
  double? _modelValueOf(String text) {
    final parsed = widget.decimal ? double.tryParse(text) : int.tryParse(text)?.toDouble();
    return parsed != null && widget.validator?.call(parsed) != null ? null : parsed;
  }

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
    final entered = double.tryParse(_controller.text);
    final error = entered == null ? null : widget.validator?.call(entered);
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        floatingLabelBehavior: widget.floating,
        errorText: error,
        isDense: true,
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(widget.decimal ? r'[0-9.]' : r'[0-9]')),
      ],
      onChanged: (text) {
        widget.onChanged(_modelValueOf(text));
        // Show or clear the error even when the model value didn't change.
        setState(() {});
      },
    );
  }
}
