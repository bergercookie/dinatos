import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A slim footer pinned to the bottom of a list screen, showing how many
/// items there are in total (e.g. "12 routines"). Meant for
/// `Scaffold.bottomNavigationBar`, so floating action buttons sit above it.
class CountFooter extends StatelessWidget {
  const CountFooter({super.key, required this.count, required this.singular, String? plural})
    : plural = plural ?? '${singular}s';

  final int count;
  final String singular;
  final String plural;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Text(
            'Total: $count ${count == 1 ? singular : plural}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
