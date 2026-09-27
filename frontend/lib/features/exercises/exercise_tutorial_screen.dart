import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_value_view.dart';
import '../../models/exercise_tutorial.dart';
import 'exercises_providers.dart';

class ExerciseTutorialScreen extends ConsumerWidget {
  const ExerciseTutorialScreen({super.key, required this.exerciseId});

  final int exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise = ref.watch(exerciseProvider(exerciseId));
    final tutorial = ref.watch(exerciseTutorialProvider(exerciseId));

    return Scaffold(
      appBar: AppBar(title: Text(exercise.valueOrNull?.name ?? 'Tutorial')),
      body: AsyncValueView(
        value: tutorial,
        onRetry: () => ref.invalidate(exerciseTutorialProvider(exerciseId)),
        builder: (context, data) {
          if (data == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No tutorial available for this exercise.'),
              ),
            );
          }
          return _TutorialView(tutorial: data);
        },
      ),
    );
  }
}

class _TutorialView extends StatelessWidget {
  const _TutorialView({required this.tutorial});

  final ExerciseTutorial tutorial;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (tutorial.gifUrls.isNotEmpty)
          SizedBox(
            height: 260,
            // A `PageView` rather than just the first image -- some
            // exercises (this backend's default free-exercise-db provider
            // included) have more than one, e.g. a start/end position pair.
            child: PageView(
              children: tutorial.gifUrls
                  .map(
                    (url) => Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Icon(Icons.broken_image_outlined, size: 48)),
                      loadingBuilder: (context, child, progress) => progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 16),
        if (tutorial.equipment != null) _Section(label: 'Equipment', body: tutorial.equipment!),
        if (tutorial.primaryMuscles.isNotEmpty)
          _Section(label: 'Primary muscles', body: tutorial.primaryMuscles.join(', ')),
        if (tutorial.secondaryMuscles.isNotEmpty)
          _Section(label: 'Secondary muscles', body: tutorial.secondaryMuscles.join(', ')),
        if (tutorial.instructions.isNotEmpty) ...[
          Text('Instructions', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (index, step) in tutorial.instructions.indexed)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${index + 1}. $step')),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          Text(body),
        ],
      ),
    );
  }
}
