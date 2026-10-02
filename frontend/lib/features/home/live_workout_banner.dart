import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_tokens.dart';
import '../activities/live/elapsed_timer.dart';
import '../activities/live/live_session.dart';

const liveWorkoutRoute = '/activities/live';

/// A persistent "workout in progress" strip shown above the bottom nav on
/// every tab while a live workout is under way, so the person can wander off
/// to routines or exercises and get back with one tap. Hidden on the live
/// workout screen itself, and once the workout has been finished.
class LiveWorkoutBanner extends ConsumerWidget {
  const LiveWorkoutBanner({super.key, required this.currentPath});

  /// The router's current location -- the banner would be redundant on the
  /// live screen it links to.
  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(liveActivityProvider);
    if (session == null || session.endedAt != null || currentPath == liveWorkoutRoute) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.titleSmall
        ?.copyWith(color: scheme.onPrimaryContainer);
    return Material(
      color: scheme.primaryContainer,
      child: InkWell(
        onTap: () => context.go(liveWorkoutRoute),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(
                session.isPaused ? Icons.pause_circle_outline : Icons.fitness_center,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  session.isPaused ? 'Workout paused' : 'Workout in progress',
                  style: textStyle,
                ),
              ),
              ElapsedTimer(since: session.clockOrigin, until: session.pausedAt, style: textStyle),
              const SizedBox(width: AppSpacing.sm),
              Text('Return', style: textStyle),
              Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
