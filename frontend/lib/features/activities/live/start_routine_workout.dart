import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/routine.dart';
import 'live_session.dart';

/// Starts a live workout pre-filled from [routine] and opens it.
///
/// [plannedWorkoutId] and [title] come from a calendar entry (see
/// `startPlannedWorkout`).
///
/// A workout already under way is never silently clobbered (the "Start
/// workout" button resumes it instead): the person chooses between carrying
/// on with it and replacing it with this routine.
Future<void> startWorkoutFromRoutine(
  BuildContext context,
  WidgetRef ref,
  Routine routine, {
  int? plannedWorkoutId,
  String? title,
}) async {
  final session = ref.read(liveActivityProvider);
  final inProgress = session != null && session.endedAt == null;

  if (inProgress) {
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout already in progress'),
        content: Text(
          'Starting "${routine.name}" will discard the workout you are currently doing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Resume current'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard and start'),
          ),
        ],
      ),
    );
    // Dismissed (null): do nothing at all.
    if (replace == null || !context.mounted) return;
    if (!replace) {
      context.go('/activities/live');
      return;
    }
  }

  ref
      .read(liveActivityProvider.notifier)
      .startFromRoutine(routine, plannedWorkoutId: plannedWorkoutId, title: title);
  context.go('/activities/live');
}
