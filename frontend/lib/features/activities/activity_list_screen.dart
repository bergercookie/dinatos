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
          onRefresh: () => ref.refresh(activityListProvider.future),
          child: AsyncValueView(
            value: activities,
            onRetry: () => ref.invalidate(activityListProvider),
            builder: (context, data) {
              if (data.isEmpty) {
                return EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No logged activities yet',
                  message: 'Log a session to start tracking what you actually did in the gym.',
                  actionLabel: 'Log activity',
                  onAction: () => context.go('/activities/new'),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                // +2 for the stats and calendar/streak cards, pinned above the list itself.
                itemCount: data.length + 2,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return StatsSummaryCard(
                      activities: data,
                      onOpenStats: () => context.go('/activities/stats'),
                    );
                  }
                  if (index == 1) return TrainingCalendarCard(activities: data);
                  final activity = data[index - 2];
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
