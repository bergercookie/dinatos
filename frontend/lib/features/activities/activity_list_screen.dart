import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/count_footer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../calendar/day_plans_sheet.dart';
import '../calendar/planned_workouts_providers.dart';
import '../calendar/upcoming_workouts_card.dart';
import '../../models/activity.dart';
import 'activities_providers.dart';
import '../onboarding/onboarding_overlay.dart';
import '../stats/stats_summary_card.dart';
import 'live/live_session.dart';
import 'live/start_activity_sheet.dart';
import 'widgets/training_calendar_card.dart';

class ActivityListScreen extends ConsumerWidget {
  const ActivityListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activityListProvider);
    // A failed or pending fetch just means no plans are shown: never worth blocking Home on.
    final plans = ref.watch(plannedWorkoutListProvider).valueOrNull ?? const [];
    final dateFormat = DateFormat.yMMMd().add_Hm();
    final liveSession = ref.watch(liveActivityProvider);
    final hasLiveWorkout = liveSession != null && liveSession.endedAt == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      floatingActionButton: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTarget(
              id: 'start-workout',
              child: FloatingActionButton.extended(
                heroTag: 'start-live-workout',
                tooltip: 'Start an interactive session as you work out',
                onPressed: () {
                  // Never clobber a workout already under way -- resume it.
                  if (hasLiveWorkout) {
                    context.go('/activities/live');
                  } else {
                    showStartActivitySheet(context, ref);
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: Text(hasLiveWorkout ? 'Resume workout' : 'Start activity'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FloatingActionButton.extended(
              heroTag: 'log-past-activity',
              tooltip: 'Log a past activity',
              onPressed: () => context.go('/activities/new'),
              icon: const Icon(Icons.add),
              label: const Text('Log activity'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: activities.whenOrNull(
        data: (data) => CountFooter(count: data.length, singular: 'activity', plural: 'activities'),
      ),
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: () {
            ref.invalidate(plannedWorkoutListProvider);
            return ref.refresh(activityListProvider.future);
          },
          child: AsyncValueView(
            value: activities,
            onRetry: () => ref.invalidate(activityListProvider),
            builder: (context, data) {
              if (data.isEmpty) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        0,
                      ),
                      child: UpcomingWorkoutsCard(plans: plans),
                    ),
                    Expanded(
                      child: EmptyState(
                        icon: Icons.history_rounded,
                        title: 'No logged activities yet',
                        message:
                            'Log a session to start tracking what you actually did in the gym.',
                        actionLabel: 'Log activity',
                        onAction: () => context.go('/activities/new'),
                      ),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                // +3 for the stats, upcoming and calendar/streak cards, pinned above the list itself.
                itemCount: data.length + 3,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return StatsSummaryCard(
                      activities: data,
                      onOpenStats: () => context.go('/activities/stats'),
                    );
                  }
                  if (index == 1) return UpcomingWorkoutsCard(plans: plans);
                  if (index == 2) {
                    return TrainingCalendarCard(
                      activities: data,
                      plannedWorkouts: plans,
                      onDayTap: (day) => showDayPlansSheet(context, ref, day, plans),
                    );
                  }
                  final activity = data[index - 3];
                  return AppListCard(
                    leading: const AppIconAvatar(icon: Icons.history_rounded),
                    title: activity.title,
                    subtitle: Text(_subtitle(activity, dateFormat)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/activities/${activity.id}'),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _subtitle(Activity activity, DateFormat dateFormat) {
    final exerciseCount = activity.exercises.length;
    final parts = <String>[
      dateFormat.format(activity.startedAt.toLocal()),
      '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'}',
    ];
    final endedAt = activity.endedAt;
    if (endedAt != null) {
      final duration = endedAt.difference(activity.startedAt);
      if (duration.inMinutes > 0) parts.add('${duration.inMinutes} min');
    }
    return parts.join(' · ');
  }
}
