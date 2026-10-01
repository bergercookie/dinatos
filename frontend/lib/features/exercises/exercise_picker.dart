import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../models/exercise.dart';

/// Opens a search-filterable picker over [exercises] and resolves with the
/// chosen [Exercise], or null if dismissed without picking one -- replaces
/// scrolling an unfiltered menu to find one exercise among the whole catalog.
Future<Exercise?> showExercisePicker(BuildContext context, {required List<Exercise> exercises}) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ExercisePickerSheet(exercises: exercises),
  );
}

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet({required this.exercises});

  final List<Exercise> exercises;

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.exercises
        : widget.exercises.where((e) => e.name.toLowerCase().contains(query)).toList();

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
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching exercises',
                        message: 'Try a different search term.',
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
