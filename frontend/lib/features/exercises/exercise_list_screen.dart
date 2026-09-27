import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_value_view.dart';
import '../../models/exercise.dart';
import 'exercises_providers.dart';

class ExerciseListScreen extends ConsumerWidget {
  const ExerciseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(exerciseListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercises'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search exercises...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => ref.read(exerciseSearchProvider.notifier).state = value,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New exercise',
        onPressed: () => context.go('/exercises/new'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(exerciseListProvider.future),
        child: AsyncValueView(
          value: exercises,
          onRetry: () => ref.invalidate(exerciseListProvider),
          builder: (context, data) {
            if (data.isEmpty) {
              return const Center(child: Text('No exercises yet.'));
            }
            return ListView.builder(
              itemCount: data.length,
              itemBuilder: (context, index) {
                final exercise = data[index];
                return ListTile(
                  title: Text(exercise.name),
                  subtitle: Text(_tracksSummary(exercise)),
                  onTap: () => context.go('/exercises/${exercise.id}/edit'),
                  trailing: IconButton(
                    tooltip: 'View tutorial',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => context.go('/exercises/${exercise.id}/tutorial'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _tracksSummary(Exercise exercise) {
    final tracked = <String>[
      if (exercise.tracksWeight) 'weight',
      if (exercise.tracksReps) 'reps',
      if (exercise.tracksDistance) 'distance',
      if (exercise.tracksDuration) 'duration',
    ];
    return tracked.isEmpty ? 'Nothing tracked' : 'Tracks: ${tracked.join(', ')}';
  }
}
