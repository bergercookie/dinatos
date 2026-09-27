import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_value_view.dart';
import 'workouts_providers.dart';

class WorkoutListScreen extends ConsumerWidget {
  const WorkoutListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workouts = ref.watch(workoutListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workouts')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New workout',
        onPressed: () => context.go('/workouts/new'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(workoutListProvider.future),
        child: AsyncValueView(
          value: workouts,
          onRetry: () => ref.invalidate(workoutListProvider),
          builder: (context, data) {
            if (data.isEmpty) {
              return const Center(child: Text('No saved workouts yet.'));
            }
            return ListView.builder(
              itemCount: data.length,
              itemBuilder: (context, index) {
                final workout = data[index];
                return ListTile(
                  title: Text(workout.name),
                  subtitle: Text('${workout.exercises.length} exercise(s)'),
                  onTap: () => context.go('/workouts/${workout.id}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
