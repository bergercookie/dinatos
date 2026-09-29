import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/workout.dart';
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
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(workoutListProvider.future),
          child: AsyncValueView(
            value: workouts,
            onRetry: () => ref.invalidate(workoutListProvider),
            builder: (context, data) {
              if (data.isEmpty) {
                return EmptyState(
                  icon: Icons.list_alt_rounded,
                  title: 'No saved workouts yet',
                  message: 'Build a workout template once, then reuse it every time you train.',
                  actionLabel: 'Create workout',
                  onAction: () => context.go('/workouts/new'),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                itemCount: data.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final workout = data[index];
                  return AppListCard(
                    leading: const AppIconAvatar(icon: Icons.list_alt_rounded),
                    title: workout.name,
                    subtitle: Text(_subtitle(workout)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/workouts/${workout.id}'),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _subtitle(Workout workout) {
    final exerciseCount = workout.exercises.length;
    final setCount = workout.exercises.fold<int>(0, (sum, e) => sum + e.sets.length);
    final exercisePart = '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'}';
    if (setCount == 0) return exercisePart;
    return '$exercisePart · $setCount set${setCount == 1 ? '' : 's'}';
  }
}
