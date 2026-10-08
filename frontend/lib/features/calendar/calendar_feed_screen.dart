import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/server_url_provider.dart';
import '../../core/widgets/responsive_body.dart';
import 'planned_workouts_providers.dart';
import 'planned_workouts_repository.dart';

/// The full URL of a calendar feed: the server's address plus the feed's [path].
String calendarFeedUrl(String serverUrl, String path) {
  final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
  return '$base$path';
}

/// Settings > Calendar feed: a private link that calendar apps subscribe to,
/// so planned workouts show up (and stay up to date) next to everything else.
class CalendarFeedScreen extends ConsumerWidget {
  const CalendarFeedScreen({super.key});

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(PlannedWorkoutsRepository) action,
  ) async {
    try {
      await action(ref.read(plannedWorkoutsRepositoryProvider));
      ref.invalidate(calendarFeedProvider);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Something went wrong: ${error.message}')));
      }
    }
  }

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a new link?'),
        content: const Text(
          'The current link stops working, so every calendar subscribed to it goes empty '
          'until you subscribe again with the new one.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, ref, (repository) => repository.enableFeed());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(calendarFeedProvider);
    final serverUrl = ref.watch(serverUrlProvider);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar feed')),
      body: ResponsiveBody(
        child: AsyncValueView(
          value: feed,
          onRetry: () => ref.invalidate(calendarFeedProvider),
          builder: (context, data) {
            final path = data.path;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  'Subscribe to this link in Google Calendar, Apple Calendar or Outlook and your '
                  'planned workouts appear there as events, with their reminders. The feed is '
                  'always current; your calendar app re-checks it on its own schedule -- about '
                  'hourly, though some (Google) only every few hours.',
                  style: muted,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (path == null) ...[
                  FilledButton.icon(
                    onPressed: () => _run(context, ref, (r) => r.enableFeed()),
                    icon: const Icon(Icons.link),
                    label: const Text('Create calendar link'),
                  ),
                ] else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: SelectableText(
                        calendarFeedUrl(serverUrl, path),
                        key: const ValueKey('feed-url'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: () async {
                      String message;
                      try {
                        await Clipboard.setData(
                          ClipboardData(text: calendarFeedUrl(serverUrl, path)),
                        );
                        message = 'Link copied';
                      } catch (_) {
                        // E.g. a browser that refuses clipboard access: the link is selectable.
                        message = 'Could not copy -- select the link and copy it by hand';
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(message)));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy link'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Anyone with this link can see your planned workouts, so keep it to yourself. '
                    'If it leaks, create a new one -- the old link stops working.',
                    style: muted,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => _regenerate(context, ref),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Create a new link'),
                  ),
                  TextButton.icon(
                    onPressed: () => _run(context, ref, (r) => r.disableFeed()),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Turn the feed off'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
