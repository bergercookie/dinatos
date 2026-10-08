import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/design_tokens.dart';
import '../../models/planned_workout.dart';
import '../activities/live/live_session.dart';
import '../activities/live/start_routine_workout.dart';
import '../routines/routines_repository.dart';
import 'planned_workouts_repository.dart';

/// Starts a live workout from a calendar entry: pre-filled from its routine
/// when it has one, empty otherwise -- and tied to the plan, so saving the
/// workout marks the plan done. Like any other start, it never silently
/// discards a workout already under way.
Future<void> startPlannedWorkout(BuildContext context, WidgetRef ref, PlannedWorkout plan) async {
  final routineId = plan.routineId;
  if (routineId != null) {
    final routine = await ref.read(routinesRepositoryProvider).get(routineId);
    if (!context.mounted) return;
    await startWorkoutFromRoutine(
      context,
      ref,
      routine,
      plannedWorkoutId: plan.id,
      title: plan.title,
    );
    return;
  }
  final session = ref.read(liveActivityProvider);
  if (session != null && session.endedAt == null) {
    // Nothing to pre-fill, so the safe thing is to carry on with the current one.
    context.go('/activities/live');
    return;
  }
  ref.read(liveActivityProvider.notifier).start(plannedWorkoutId: plan.id, title: plan.title);
  context.go('/activities/live');
}

/// The lowest-friction way into a planned workout: the route a reminder
/// notification opens. Loads the plan, starts it and moves on to the live
/// workout; shows why not when it cannot.
class StartPlannedWorkoutScreen extends ConsumerStatefulWidget {
  const StartPlannedWorkoutScreen({super.key, required this.plannedId});

  final int plannedId;

  @override
  ConsumerState<StartPlannedWorkoutScreen> createState() => _StartPlannedWorkoutScreenState();
}

class _StartPlannedWorkoutScreenState extends ConsumerState<StartPlannedWorkoutScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final plan = await ref.read(plannedWorkoutsRepositoryProvider).get(widget.plannedId);
      if (!mounted) return;
      if (plan.isCompleted) {
        context.go('/activities');
        return;
      }
      await startPlannedWorkout(context, ref, plan);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Starting workout')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not start the planned workout: $error'),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(onPressed: _start, child: const Text('Try again')),
                    TextButton(
                      onPressed: () => context.go('/activities'),
                      child: const Text('Back to Home'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
