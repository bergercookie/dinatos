import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/async_value_view.dart';
import 'activities_providers.dart';

class ActivityListScreen extends ConsumerWidget {
  const ActivityListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activityListProvider);
    final dateFormat = DateFormat.yMMMd().add_Hm();

    return Scaffold(
      appBar: AppBar(title: const Text('Activities')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New activity',
        onPressed: () => context.go('/activities/new'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(activityListProvider.future),
        child: AsyncValueView(
          value: activities,
          onRetry: () => ref.invalidate(activityListProvider),
          builder: (context, data) {
            if (data.isEmpty) {
              return const Center(child: Text('No logged activities yet.'));
            }
            return ListView.builder(
              itemCount: data.length,
              itemBuilder: (context, index) {
                final activity = data[index];
                return ListTile(
                  title: Text(activity.title),
                  subtitle: Text(
                    '${dateFormat.format(activity.startedAt.toLocal())} · '
                    '${activity.exercises.length} exercise(s)',
                  ),
                  onTap: () => context.go('/activities/${activity.id}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
