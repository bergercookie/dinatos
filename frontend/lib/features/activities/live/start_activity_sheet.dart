import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_tokens.dart';
import '../../../core/api_exception.dart';
import '../../../models/planned_workout.dart';
import '../../../models/routine.dart';
import '../../calendar/planned_workouts_providers.dart';
import '../../calendar/start_planned_workout.dart';
import '../../routines/routines_providers.dart';
import 'live_session.dart';
import 'start_routine_workout.dart';

enum _StartChoice { routine, scratch, planned }

/// Offers the ways to start an activity: copy one of the saved routines as is
/// ("Use routine"), or start empty ("From scratch") -- and, on a day with a
/// workout planned on the calendar, a third: the "Planned workout" itself.
Future<void> showStartActivitySheet(BuildContext context, WidgetRef ref) async {
  // Whatever the Home screen has already loaded: never worth making the sheet wait for.
  final planned = todaysPlannedWorkouts(
    ref.read(plannedWorkoutListProvider).valueOrNull ?? const [],
    DateTime.now(),
  );
  final choice = await showModalBottomSheet<_StartChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (planned.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.event_available_rounded),
              title: const Text('Planned workout'),
              subtitle: Text(plannedSubtitle(planned, MaterialLocalizations.of(context))),
              onTap: () => Navigator.of(context).pop(_StartChoice.planned),
            ),
          ListTile(
            leading: const Icon(Icons.list_alt_rounded),
            title: const Text('Use routine'),
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
    case _StartChoice.planned:
      PlannedWorkout? plan = planned.first;
      if (planned.length > 1) {
        plan = await showModalBottomSheet<PlannedWorkout>(
          context: context,
          showDragHandle: true,
          builder: (context) => _PlannedPicker(plans: planned),
        );
      }
      if (plan == null || !context.mounted) return;
      try {
        await startPlannedWorkout(context, ref, plan);
      } on ApiException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start the planned workout: ${error.message}')),
          );
        }
      }
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

/// "Push · 18:00", or "2 planned today" when there are several.
String plannedSubtitle(List<PlannedWorkout> plans, MaterialLocalizations l10n) {
  if (plans.length > 1) return '${plans.length} planned today';
  final plan = plans.single;
  final time = l10n.formatTimeOfDay(TimeOfDay.fromDateTime(plan.scheduledAt));
  return '${plan.title} · $time';
}

class _PlannedPicker extends StatelessWidget {
  const _PlannedPicker({required this.plans});

  final List<PlannedWorkout> plans;

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final plan in plans)
            ListTile(
              leading: const Icon(Icons.event_available_rounded),
              title: Text(plan.title),
              subtitle: Text(l10n.formatTimeOfDay(TimeOfDay.fromDateTime(plan.scheduledAt))),
              onTap: () => Navigator.of(context).pop(plan),
            ),
        ],
      ),
    );
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
