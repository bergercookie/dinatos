import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_value_view.dart';
import '../../core/design_tokens.dart';
import '../../core/widgets/app_list_card.dart';
import '../../core/widgets/count_footer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/routine.dart';
import '../onboarding/onboarding_overlay.dart';
import 'routines_providers.dart';

class RoutineListScreen extends ConsumerWidget {
  const RoutineListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routineListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Routines')),
      floatingActionButton: OnboardingTarget(
        id: 'routines-new',
        child: FloatingActionButton(
          tooltip: 'New routine',
          onPressed: () => context.go('/routines/new'),
          child: const Icon(Icons.add),
        ),
      ),
      bottomNavigationBar: routines.whenOrNull(
        data: (data) => CountFooter(count: data.length, singular: 'routine'),
      ),
      body: ResponsiveBody(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(routineListProvider.future),
          child: AsyncValueView(
            value: routines,
            onRetry: () => ref.invalidate(routineListProvider),
            builder: (context, data) {
              if (data.isEmpty) {
                return EmptyState(
                  icon: Icons.list_alt_rounded,
                  title: 'No saved routines yet',
                  message: 'Build a routine template once, then reuse it every time you train.',
                  actionLabel: 'Create routine',
                  onAction: () => context.go('/routines/new'),
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
                  final routine = data[index];
                  return AppListCard(
                    leading: const AppIconAvatar(icon: Icons.list_alt_rounded),
                    title: routine.name,
                    subtitle: Text(_subtitle(routine)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/routines/${routine.id}'),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _subtitle(Routine routine) {
    final exerciseCount = routine.exercises.length;
    final setCount = routine.exercises.fold<int>(0, (sum, e) => sum + e.sets.length);
    final exercisePart = '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'}';
    if (setCount == 0) return exercisePart;
    return '$exercisePart · $setCount set${setCount == 1 ? '' : 's'}';
  }
}
