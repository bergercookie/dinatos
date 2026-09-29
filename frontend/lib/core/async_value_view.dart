import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_exception.dart';
import 'design_tokens.dart';

/// The loading/error/data switch every list screen needs for its
/// `FutureProvider`, in one place instead of repeated per screen.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({super.key, required this.value, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (data) => builder(context, data),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) {
        final scheme = Theme.of(context).colorScheme;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 40, color: scheme.error),
                const SizedBox(height: AppSpacing.md),
                Text(
                  error is ApiException ? error.message : 'Something went wrong.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
