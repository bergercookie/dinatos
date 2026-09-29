import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/exercise.dart';
import 'exercises_providers.dart';

class ExerciseListScreen extends ConsumerWidget {
  const ExerciseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(exerciseListProvider);
    final searching = ref.watch(exerciseSearchProvider).isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Exercises')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New exercise',
        onPressed: () => context.go('/exercises/new'),
        child: const Icon(Icons.add),
      ),
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(exerciseListProvider.future),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search exercises...',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (value) => ref.read(exerciseSearchProvider.notifier).state = value,
                ),
              ),
              Expanded(
                child: AsyncValueView(
                  value: exercises,
                  onRetry: () => ref.invalidate(exerciseListProvider),
                  builder: (context, data) {
                    if (data.isEmpty) {
                      return EmptyState(
                        icon: searching ? Icons.search_off_rounded : Icons.fitness_center_rounded,
                        title: searching ? 'No matching exercises' : 'No exercises yet',
                        message: searching
                            ? 'Try a different search term.'
                            : 'Add the exercises you train so you can build workouts around them.',
                        actionLabel: searching ? null : 'Add exercise',
                        onAction: searching ? null : () => context.go('/exercises/new'),
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
                        final exercise = data[index];
                        return AppListCard(
                          leading: const AppIconAvatar(icon: Icons.fitness_center_rounded),
                          title: exercise.name,
                          subtitle: _TrackedChips(exercise: exercise),
                          trailing: IconButton(
                            tooltip: 'View tutorial',
                            icon: const Icon(Icons.play_circle_outline_rounded),
                            onPressed: () => context.go('/exercises/${exercise.id}/tutorial'),
                          ),
                          onTap: () => context.go('/exercises/${exercise.id}/edit'),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackedChips extends StatelessWidget {
  const _TrackedChips({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final tracked = <String>[
      if (exercise.tracksWeight) 'Weight',
      if (exercise.tracksReps) 'Reps',
      if (exercise.tracksDistance) 'Distance',
      if (exercise.tracksDuration) 'Duration',
    ];
    if (tracked.isEmpty) return const Text('Nothing tracked');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: tracked.map((label) => Chip(label: Text(label))).toList(),
      ),
    );
  }
}
