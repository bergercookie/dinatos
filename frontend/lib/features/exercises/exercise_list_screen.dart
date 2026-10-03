import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/count_footer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/exercise.dart';
import 'exercises_providers.dart';

class ExerciseListScreen extends ConsumerStatefulWidget {
  const ExerciseListScreen({super.key});

  @override
  ConsumerState<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends ConsumerState<ExerciseListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Fires a bit before the true end so the next page is usually already
    // loading by the time a person scrolls into view of the last item.
    _scrollController.addListener(() {
      if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 400) {
        ref.read(exercisePagingProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exercisePagingProvider);
    final searching = state.search.isNotEmpty || state.source != ExerciseSource.all;

    return Scaffold(
      appBar: AppBar(title: const Text('Exercises')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New exercise',
        onPressed: () => context.go('/exercises/new'),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: state.loading || state.error != null && state.items.isEmpty
          ? null
          : CountFooter(
              count: state.total,
              singular: searching ? 'matching exercise' : 'exercise',
              plural: searching ? 'matching exercises' : 'exercises',
            ),
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: () => ref.read(exercisePagingProvider.notifier).refresh(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search exercises...',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (value) => ref.read(exercisePagingProvider.notifier).setSearch(value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final source in ExerciseSource.values)
                        ChoiceChip(
                          label: Text(source.label),
                          selected: state.source == source,
                          onSelected: (_) =>
                              ref.read(exercisePagingProvider.notifier).setSource(source),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _buildBody(context, state, searching: searching)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ExercisePageState state, {required bool searching}) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      final error = state.error;
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: scheme.error),
              const SizedBox(height: AppSpacing.md),
              Text(
                error is ApiException ? error.message : 'Something went wrong.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonal(
                onPressed: () => ref.read(exercisePagingProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (state.items.isEmpty) {
      return EmptyState(
        icon: searching ? Icons.search_off_rounded : Icons.fitness_center_rounded,
        title: searching ? 'No matching exercises' : 'No exercises yet',
        message: searching
            ? 'Try a different search term or filter.'
            : 'Add the exercises you train so you can build routines around them.',
        actionLabel: searching ? null : 'Add exercise',
        onAction: searching ? null : () => context.go('/exercises/new'),
      );
    }
    // +1 for a trailing loading/end-of-list row, whenever there's something
    // to say about it (more to load, or a load-more error).
    final showFooter = state.hasMore || state.loadingMore || state.error != null;
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: state.items.length + (showFooter ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return _ListFooter(state: state);
        }
        final exercise = state.items[index];
        return AppListCard(
          leading: AppIconAvatar(
            icon: exercise.isCustom ? Icons.fitness_center_rounded : Icons.verified_rounded,
            background: exercise.isCustom ? null : Theme.of(context).colorScheme.secondaryContainer,
            color: exercise.isCustom ? null : Theme.of(context).colorScheme.onSecondaryContainer,
          ),
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
  }
}

class _ListFooter extends ConsumerWidget {
  const _ListFooter({required this.state});

  final ExercisePageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: TextButton.icon(
            onPressed: () => ref.read(exercisePagingProvider.notifier).loadMore(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(child: CircularProgressIndicator()),
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
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (!exercise.isCustom)
            Chip(
              avatar: const Icon(Icons.verified_rounded, size: 16),
              label: const Text('Built-in'),
              visualDensity: VisualDensity.compact,
            ),
          if (tracked.isEmpty) const Text('Nothing tracked'),
          ...tracked.map((label) => Chip(label: Text(label))),
        ],
      ),
    );
  }
}
