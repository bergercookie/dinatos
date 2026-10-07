import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../models/equipment.dart';
import '../../models/exercise.dart';
import '../../models/muscle_group.dart';
import '../activities/activities_providers.dart';
import 'exercises_providers.dart';

/// Opens a picker over [exercises] and resolves with the chosen [Exercise],
/// or null if dismissed without picking one -- replaces scrolling an
/// unfiltered menu to find one exercise among the whole catalog. Narrows by
/// name search, by the muscles an exercise trains (primary or secondary), and
/// by equipment, and by whether it is built-in or custom; within one filter any selected value matches, across
/// filters all must. Results are ordered by how often the person has logged
/// each exercise, most-used first (the catalog's own order breaks ties).
///
/// [initialQuery] pre-fills the search box (e.g. with what was dictated).
Future<Exercise?> showExercisePicker(
  BuildContext context, {
  required List<Exercise> exercises,
  String initialQuery = '',
}) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ExercisePickerSheet(exercises: exercises, initialQuery: initialQuery),
  );
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  const _ExercisePickerSheet({required this.exercises, required this.initialQuery});

  final List<Exercise> exercises;
  final String initialQuery;

  @override
  ConsumerState<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<_ExercisePickerSheet> {
  late final _searchController = TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery;
  final Set<MuscleGroup> _muscles = {};
  final Set<Equipment> _equipment = {};
  ExerciseSource _source = ExerciseSource.all;

  bool _matches(Exercise e, String query) {
    if (query.isNotEmpty && !e.name.toLowerCase().contains(query)) return false;
    if (_muscles.isNotEmpty &&
        !e.primaryMuscles.any(_muscles.contains) &&
        !e.secondaryMuscles.any(_muscles.contains)) {
      return false;
    }
    if (_equipment.isNotEmpty && !_equipment.contains(e.equipment)) return false;
    return _source.matches(e);
  }

  Widget _chipRow<T>(String label, List<T> values, Set<T> selected, String Function(T) labelOf) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final value in values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: FilterChip(
                      label: Text(labelOf(value)),
                      selected: selected.contains(value),
                      onSelected: (on) => setState(() {
                        on ? selected.add(value) : selected.remove(value);
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final usage = ref.watch(exerciseUsageProvider).valueOrNull ?? const <int, int>{};
    // List.sort is not stable, so tie-break on the catalog position.
    final order = {for (var i = 0; i < widget.exercises.length; i++) widget.exercises[i]: i};
    final filtered = widget.exercises.where((e) => _matches(e, query)).toList()
      ..sort((a, b) {
        final byUse = (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
        return byUse != 0 ? byUse : order[a]!.compareTo(order[b]!);
      });

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add exercise', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search exercises...',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              _chipRow('Muscle', MuscleGroup.values, _muscles, (m) => m.label),
              _chipRow('Equipment', Equipment.values, _equipment, (e) => e.label),
              Row(
                children: [
                  Text('Source', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(width: AppSpacing.sm),
                  for (final source in ExerciseSource.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: ChoiceChip(
                        label: Text(source.label),
                        selected: _source == source,
                        onSelected: (_) => setState(() => _source = source),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching exercises',
                        message: 'Try a different search term or clear a filter.',
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final exercise = filtered[index];
                          return AppListCard(
                            leading: AppIconAvatar(
                              icon: exercise.isCustom
                                  ? Icons.fitness_center_rounded
                                  : Icons.verified_rounded,
                              background: exercise.isCustom
                                  ? null
                                  : Theme.of(context).colorScheme.secondaryContainer,
                              color: exercise.isCustom
                                  ? null
                                  : Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                            title: exercise.name,
                            onTap: () => Navigator.of(context).pop(exercise),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
