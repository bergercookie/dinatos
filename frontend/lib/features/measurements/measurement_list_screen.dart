import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_exception.dart';
import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/measurement.dart';
import 'measurements_providers.dart';
import 'measurements_repository.dart';

class MeasurementListScreen extends ConsumerWidget {
  const MeasurementListScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, BodyMeasurement measurement) async {
    try {
      await ref.read(measurementsRepositoryProvider).delete(measurement.id!);
      ref.invalidate(measurementListProvider);
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measurements = ref.watch(measurementListProvider);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('Measurements')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New measurement',
        onPressed: () => context.go('/measurements/new'),
        child: const Icon(Icons.add),
      ),
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(measurementListProvider.future),
          child: AsyncValueView(
            value: measurements,
            onRetry: () => ref.invalidate(measurementListProvider),
            builder: (context, data) {
              if (data.isEmpty) {
                return EmptyState(
                  icon: Icons.straighten_rounded,
                  title: 'No measurements logged yet',
                  message: 'Track weight and body measurements over time to see your progress.',
                  actionLabel: 'Add measurement',
                  onAction: () => context.go('/measurements/new'),
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
                  final measurement = data[index];
                  final subtitleParts = <String>[
                    if (measurement.weightKg != null) '${measurement.weightKg} kg',
                    if (measurement.fatPercent != null) '${measurement.fatPercent}% fat',
                  ];
                  return Dismissible(
                    key: ValueKey(measurement.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    onDismissed: (_) => _delete(context, ref, measurement),
                    child: AppListCard(
                      leading: const AppIconAvatar(icon: Icons.straighten_rounded),
                      title: dateFormat.format(measurement.measuredAt.toLocal()),
                      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
