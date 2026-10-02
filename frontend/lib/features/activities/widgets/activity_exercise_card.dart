import 'package:flutter/material.dart';

import '../../../models/activity.dart';
import '../../../models/set_type.dart';

/// One exercise's card within an activity being built up -- its name, its
/// sets so far (weight/reps/set-type), and controls to add/remove either.
/// Shared by [ActivityFormScreen] (a whole activity, built then submitted
/// once) and the live workout screen (sets added one at a time as they're
/// actually performed) -- the editing surface is identical either way.
class ActivityExerciseCard extends StatelessWidget {
  const ActivityExerciseCard({
    super.key,
    required this.exercise,
    required this.exerciseName,
    required this.onChanged,
    required this.onRemove,
  });

  final ActivityExercise exercise;
  final String? exerciseName;
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
                    exerciseName ?? '#${exercise.exerciseId}',
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
            for (var i = 0; i < exercise.sets.length; i++)
              ActivitySetRow(
                index: i,
                set: exercise.sets[i],
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

class ActivitySetRow extends StatelessWidget {
  const ActivitySetRow({
    super.key,
    required this.index,
    required this.set,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final ActivitySet set;
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
