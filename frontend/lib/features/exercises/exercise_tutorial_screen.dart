import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/async_value_view.dart';
import '../../core/widgets/responsive_body.dart';
import '../../models/exercise_tutorial.dart';
import 'exercises_providers.dart';

/// Swipe/flick needs to clear this (in logical pixels per second) to count
/// as a page-to-page gesture rather than an incidental drag while scrolling
/// or dismissing the gif carousel above.
const _swipeVelocityThreshold = 300.0;

class ExerciseTutorialScreen extends ConsumerStatefulWidget {
  const ExerciseTutorialScreen({super.key, required this.exerciseId});

  final int exerciseId;

  @override
  ConsumerState<ExerciseTutorialScreen> createState() => _ExerciseTutorialScreenState();
}

class _ExerciseTutorialScreenState extends ConsumerState<ExerciseTutorialScreen> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exerciseId = widget.exerciseId;
    final exercise = ref.watch(exerciseProvider(exerciseId));
    // The whole, unfiltered catalog -- same provider the routine/activity
    // pickers use -- rather than exercisePagingProvider's partial, search-
    // scoped page: next/previous needs a stable, complete ordering, not
    // whatever page the list screen happened to have loaded.
    final catalog = ref.watch(exerciseListProvider).valueOrNull;
    final tutorial = ref.watch(exerciseTutorialProvider(exerciseId));

    int? previousId;
    int? nextId;
    if (catalog != null) {
      final index = catalog.indexWhere((e) => e.id == exerciseId);
      if (index != -1) {
        if (index > 0) previousId = catalog[index - 1].id;
        if (index < catalog.length - 1) nextId = catalog[index + 1].id;
      }
    }

    void goToPrevious() {
      if (previousId != null) context.go('/exercises/$previousId/tutorial');
    }

    void goToNext() {
      if (nextId != null) context.go('/exercises/$nextId/tutorial');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.valueOrNull?.name ?? 'Tutorial'),
        actions: [
          IconButton(
            tooltip: 'Previous exercise',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: previousId == null ? null : goToPrevious,
          ),
          IconButton(
            tooltip: 'Next exercise',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: nextId == null ? null : goToNext,
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is! KeyDownEvent) return;
          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowLeft:
              goToPrevious();
            case LogicalKeyboardKey.arrowRight:
              goToNext();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            // A swipe right (finger moves right, positive velocity) goes to
            // the previous exercise, mirroring a "back" gesture; a swipe
            // left goes forward -- the same convention as flipping through
            // photos.
            if (velocity > _swipeVelocityThreshold) {
              goToPrevious();
            } else if (velocity < -_swipeVelocityThreshold) {
              goToNext();
            }
          },
          child: ResponsiveBody(
            child: AsyncValueView(
              value: tutorial,
              onRetry: () => ref.invalidate(exerciseTutorialProvider(exerciseId)),
              builder: (context, data) {
                if (data == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No tutorial available for this exercise.'),
                    ),
                  );
                }
                return _TutorialView(tutorial: data);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorialView extends StatelessWidget {
  const _TutorialView({required this.tutorial});

  final ExerciseTutorial tutorial;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (tutorial.gifUrls.isNotEmpty)
          SizedBox(
            height: 260,
            // A `PageView` rather than just the first image -- some
            // exercises (this backend's default free-exercise-db provider
            // included) have more than one, e.g. a start/end position pair.
            child: PageView(
              children: tutorial.gifUrls
                  .map(
                    (url) => Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Icon(Icons.broken_image_outlined, size: 48)),
                      loadingBuilder: (context, child, progress) => progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 16),
        if (tutorial.equipment != null) _Section(label: 'Equipment', body: tutorial.equipment!),
        if (tutorial.primaryMuscles.isNotEmpty)
          _Section(label: 'Primary muscles', body: tutorial.primaryMuscles.join(', ')),
        if (tutorial.secondaryMuscles.isNotEmpty)
          _Section(label: 'Secondary muscles', body: tutorial.secondaryMuscles.join(', ')),
        if (tutorial.instructions.isNotEmpty) ...[
          Text('Instructions', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (index, step) in tutorial.instructions.indexed)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${index + 1}. $step')),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          Text(body),
        ],
      ),
    );
  }
}
