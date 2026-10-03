import 'package:flutter/material.dart';

import '../../../models/activity.dart';
import '../../../models/equipment.dart';
import '../../../models/exercise.dart';
import '../../../models/set_type.dart';
import '../../exercises/exercise_filter_sheet.dart';

/// One exercise's card within an activity being built up -- its name, its
/// sets so far (weight/reps/set-type), and controls to add/remove either.
/// Shared by [ActivityFormScreen] (a whole activity, built then submitted
/// once) and the live workout screen (sets added one at a time as they're
/// actually performed) -- the editing surface is identical either way.
class ActivityExerciseCard extends StatelessWidget {
  const ActivityExerciseCard({
    super.key,
    required this.exercise,
    required this.catalogExercise,
    required this.onChanged,
    required this.onRemove,
  });

  final ActivityExercise exercise;

  /// The full catalog `Exercise` this activity exercise points at -- `null`
  /// only while the catalog is still loading. Carries the equipment/muscle
  /// metadata the chips below are built from, not just the name.
  final Exercise? catalogExercise;
  final ValueChanged<ActivityExercise> onChanged;
  final VoidCallback onRemove;

  void _addSet() {
    onChanged(exercise.copyWith(sets: [...exercise.sets, const ActivitySet()]));
  }

  void _removeSetAt(int index) {
    onChanged(exercise.copyWith(sets: List.of(exercise.sets)..removeAt(index)));
  }

  void _updateSetAt(int index, ActivitySet updated) {
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
                    catalogExercise?.name ?? '#${exercise.exerciseId}',
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
            if (catalogExercise != null) _ExerciseMetadataChips(exercise: catalogExercise!),
            for (var i = 0; i < exercise.sets.length; i++)
              ActivitySetRow(
                index: i,
                set: exercise.sets[i],
                weightEnabled: catalogExercise?.equipment != Equipment.bodyOnly,
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

class ActivitySetRow extends StatelessWidget {
  const ActivitySetRow({
    super.key,
    required this.index,
    required this.set,
    required this.onChanged,
    required this.onRemove,
    this.weightEnabled = true,
  });

  final int index;
  final ActivitySet set;

  /// `false` for a body-weight exercise: there is no load to enter.
  final bool weightEnabled;
  final ValueChanged<ActivitySet> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('${index + 1}.'),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: set.weightKg?.toString(),
            enabled: weightEnabled,
            decoration: const InputDecoration(labelText: 'kg', isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) => onChanged(set.copyWith(weightKg: double.tryParse(value))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: set.reps?.toString(),
            decoration: const InputDecoration(labelText: 'reps', isDense: true),
            keyboardType: TextInputType.number,
            onChanged: (value) => onChanged(set.copyWith(reps: int.tryParse(value))),
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
