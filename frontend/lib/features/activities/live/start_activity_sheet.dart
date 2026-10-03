import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_tokens.dart';
import '../../../models/routine.dart';
import '../../routines/routines_providers.dart';
import 'live_session.dart';
import 'start_routine_workout.dart';

enum _StartChoice { routine, scratch }

/// Offers the two ways to start an activity: copy one of the saved routines
/// as is ("Use workout"), or start empty ("From scratch").
Future<void> showStartActivitySheet(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<_StartChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.list_alt_rounded),
            title: const Text('Use workout'),
            subtitle: const Text('Copy a saved routine: its exercises, sets and reps'),
            onTap: () => Navigator.of(context).pop(_StartChoice.routine),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_rounded),
            title: const Text('From scratch'),
            subtitle: const Text('Start empty and add exercises as you go'),
            onTap: () => Navigator.of(context).pop(_StartChoice.scratch),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case _StartChoice.scratch:
      ref.read(liveActivityProvider.notifier).start();
      context.go('/activities/live');
    case _StartChoice.routine:
      final routine = await showModalBottomSheet<Routine>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => const _RoutinePicker(),
      );
      if (routine == null || !context.mounted) return;
      await startWorkoutFromRoutine(context, ref, routine);
  }
}

class _RoutinePicker extends ConsumerWidget {
  const _RoutinePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routineListProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: routines.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Text('Could not load your routines.'),
          ),
          data: (data) {
            if (data.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text('You have no routines yet. Create one, or start from scratch.'),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final routine in data)
                  ListTile(
                    leading: const Icon(Icons.list_alt_rounded),
                    title: Text(routine.name),
                    subtitle: Text(
                      '${routine.exercises.length} exercise'
                      '${routine.exercises.length == 1 ? '' : 's'}',
                    ),
                    onTap: () => Navigator.of(context).pop(routine),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
