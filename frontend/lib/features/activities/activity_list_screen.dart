import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/activity.dart';
import 'activities_providers.dart';

class ActivityListScreen extends ConsumerWidget {
  const ActivityListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activityListProvider);
    final dateFormat = DateFormat.yMMMd().add_Hm();

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New activity',
        onPressed: () => context.go('/activities/new'),
        child: const Icon(Icons.add),
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
                itemCount: data.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final activity = data[index];
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
