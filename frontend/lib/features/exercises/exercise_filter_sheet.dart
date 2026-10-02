import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_value_view.dart';
import '../../models/equipment.dart';
import '../../models/exercise.dart';
import '../../models/muscle_group.dart';
import 'exercises_providers.dart';

/// Opened from a tappable muscle/equipment chip (see
/// `ActivityExerciseCard`) -- lists every exercise that trains that muscle,
/// or uses that equipment, so tapping a chip answers "what else works this"
/// instead of merely labeling the exercise it's on.
class ExerciseFilterSheet extends ConsumerWidget {
  const ExerciseFilterSheet.muscle(MuscleGroup this.muscle, {super.key}) : equipment = null;

  const ExerciseFilterSheet.equipment(Equipment this.equipment, {super.key}) : muscle = null;

  final MuscleGroup? muscle;
  final Equipment? equipment;

  static Future<void> showForMuscle(BuildContext context, MuscleGroup muscle) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExerciseFilterSheet.muscle(muscle),
    );
  }

  static Future<void> showForEquipment(BuildContext context, Equipment equipment) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExerciseFilterSheet.equipment(equipment),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muscle = this.muscle;
    final equipment = this.equipment;
    final title = muscle != null ? 'Trains ${muscle.label}' : 'Uses ${equipment!.label}';
    final exercisesAsync = muscle != null
        ? ref.watch(exercisesByMuscleProvider(muscle))
        : ref.watch(exercisesByEquipmentProvider(equipment!));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncValueView(
                value: exercisesAsync,
                builder: (context, exercises) =>
                    _ExerciseResults(exercises: exercises, scrollController: scrollController),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseResults extends StatelessWidget {
  const _ExerciseResults({required this.exercises, required this.scrollController});

  final List<Exercise> exercises;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) {
      return const Center(child: Text('No exercises found'));
    }
    return ListView.builder(
      controller: scrollController,
      itemCount: exercises.length,
      itemBuilder: (context, index) {
        final exercise = exercises[index];
        return ListTile(
          title: Text(exercise.name),
          onTap: () {
            Navigator.of(context).pop();
            context.push('/exercises/${exercise.id}/tutorial');
          },
        );
      },
    );
  }
}
