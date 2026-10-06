import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens.dart';
import '../local/local_mode.dart';
import '../local/local_mode_actions.dart';

/// The one place the "how do I move to a server later" steps are written, so
/// the start-up choice, the Settings dialog and the reminder after switching
/// can never disagree.
const movingToAServerSteps = [
  'In Settings, choose "Export my data" and save the file somewhere you can reach from '
      'the server -- your files, or sent to yourself.',
  'In Settings, choose "Move to a server", then enter your server\'s address and log in '
      '(or register).',
  'Once logged in, go to Settings > "Import my data", pick the file and choose Merge.',
];

class _NumberedSteps extends StatelessWidget {
  const _NumberedSteps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text('${i + 1}. ${steps[i]}'),
          ),
      ],
    );
  }
}

/// Asked before choosing "Use without a server": what that means, what is
/// not available, and exactly how to move to a server afterwards. Resolves
/// true when the person accepts.
Future<bool> confirmLocalMode(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Use without a server?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Everything -- your routines, workouts and measurements -- is stored only on '
              'this device. There is no account and no sync, and no backup: if you uninstall '
              'the app or clear its data, it is gone.',
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Not available without a server: the Hevy import, exercise tutorials, using '
              'several devices, and administration.',
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Moving to a server later', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            const _NumberedSteps(movingToAServerSteps),
            const SizedBox(height: AppSpacing.sm),
            const Text('You can export your data at any time, so nothing locks you in.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Use without a server'),
        ),
      ],
    ),
  );
  return accepted ?? false;
}

enum MoveToServerChoice { export, switchNow }

/// Settings > "Move to a server" in local mode. Resolves [MoveToServerChoice.export]
/// to save the file first, [MoveToServerChoice.switchNow] to carry on to the
/// server setup, or null if dismissed.
Future<MoveToServerChoice?> askMoveToServer(BuildContext context) {
  return showDialog<MoveToServerChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Move to a server'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your data does not move by itself: a server starts out empty. Carry it over '
              'with a file:',
            ),
            const SizedBox(height: AppSpacing.sm),
            const _NumberedSteps(movingToAServerSteps),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Your data stays on this device after you switch, so nothing is lost if you '
              'change your mind -- choose "Use without a server" on the login screen to come '
              'back to it.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, MoveToServerChoice.export),
          child: const Text('Export my data first'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, MoveToServerChoice.switchNow),
          child: const Text('Continue to server setup'),
        ),
      ],
    ),
  );
}

/// On the login and register screens after leaving local mode: the step that
/// is easy to forget, until it is done or dismissed.
class PendingLocalImportBanner extends ConsumerWidget {
  const PendingLocalImportBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(pendingLocalImportProvider)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bringing your data from this device',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: AppSpacing.xs),
            DefaultTextStyle.merge(
              style: TextStyle(color: scheme.onSecondaryContainer),
              child: const _NumberedSteps([
                'Connect to your server below and log in (or register).',
                'In Settings, choose "Import my data" and pick the file you exported.',
              ]),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => clearPendingLocalImport(ref),
                child: const Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
