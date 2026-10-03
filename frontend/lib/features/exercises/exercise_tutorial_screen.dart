import 'dart:async';

import 'package:flutter/foundation.dart';
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
          SizedBox(height: 260, child: _FrameCarousel(urls: tutorial.gifUrls)),
        _SourceNote(source: tutorial.source),
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

/// How long each frame of a multi-image tutorial shows before the next.
const _frameDuration = Duration(milliseconds: 800);

/// The tutorial's image(s). A single URL (e.g. a WorkoutX GIF, which animates
/// itself) is just shown. Several (free-exercise-db's start/end position
/// pair) alternate automatically, flip-book style, for a GIF-like effect;
/// tapping pauses/resumes. With the OS "reduce motion" setting on it never
/// auto-plays, and a tap steps to the next frame instead.
///
/// Not a `PageView`: a horizontal swipe on this screen already means
/// "next/previous exercise", so a swipeable carousel would fight it.
class _FrameCarousel extends ConsumerStatefulWidget {
  const _FrameCarousel({required this.urls});

  final List<String> urls;

  @override
  ConsumerState<_FrameCarousel> createState() => _FrameCarouselState();
}

class _FrameCarouselState extends ConsumerState<_FrameCarousel> {
  Timer? _timer;
  int _index = 0;
  bool _paused = false;
  bool _reduceMotion = false;

  bool get _multiple => widget.urls.length > 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _syncTimer();
  }

  @override
  void didUpdateWidget(_FrameCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) {
      _index = 0;
      _paused = false;
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (_multiple && !_paused && !_reduceMotion) {
      _timer = Timer.periodic(_frameDuration, (_) => _advance());
    }
  }

  void _advance() {
    if (!mounted) return;
    setState(() => _index = (_index + 1) % widget.urls.length);
  }

  void _onTap() {
    if (!_multiple) return;
    if (_reduceMotion) {
      _advance();
    } else {
      setState(() => _paused = !_paused);
      _syncTimer();
    }
  }

  /// "Start"/"End" for the usual two-frame pair, "2/3" etc. otherwise.
  String get _label {
    final count = widget.urls.length;
    if (count == 2) return _index == 0 ? 'Start' : 'End';
    return '${_index + 1}/$count';
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.urls[_index];
    const brokenImage = Center(child: Icon(Icons.broken_image_outlined, size: 48));
    const loading = Center(child: CircularProgressIndicator());
    // A path on our own backend (e.g. a WorkoutX GIF, which needs the
    // user's API key the backend holds) is fetched with the bearer token;
    // anything else is a public URL.
    final Widget content = url.startsWith('/')
        ? ref
              .watch(tutorialMediaProvider(url))
              .when(
                data: (bytes) => Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) => brokenImage,
                ),
                loading: () => loading,
                error: (error, stackTrace) => brokenImage,
              )
        : Image.network(
            url,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) => brokenImage,
            loadingBuilder: (context, child, progress) => progress == null ? child : loading,
          );
    final image = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(url), child: content),
    );
    if (!_multiple) return image;

    final textTheme = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Stack(
        children: [
          Positioned.fill(child: image),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_label, style: textTheme.labelMedium),
                if (_paused && !_reduceMotion) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.pause_circle_outline_rounded, size: 16),
                ],
                const SizedBox(width: 8),
                for (var i = 0; i < widget.urls.length; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where this tutorial's images and text came from, with a hoverable (tap on
/// touch screens) "?" icon spelling out the details -- the provider is the
/// backend's choice (see `ExerciseTutorial.source`), so the person looking
/// at it has no other way to tell which one they are seeing.
class _SourceNote extends StatelessWidget {
  const _SourceNote({required this.source});

  final String source;

  static const _sources = {
    'free_exercise_db': (
      'free-exercise-db',
      'Images and instructions come from free-exercise-db '
          '(github.com/yuhonas/free-exercise-db), a public-domain exercise '
          'dataset bundled with this server. It has no animated GIFs, so the '
          'start and end positions of the movement alternate; tap to pause.',
    ),
    'workoutx': (
      'WorkoutX',
      'Animated GIFs and instructions come from WorkoutX (workoutxapp.com), '
          "using this server's own API key.",
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (label, details) = _sources[source] ?? (source, 'Provided by $source.');
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Source: $label', style: style),
          const SizedBox(width: 4),
          Tooltip(
            message: details,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 6),
            child: Icon(Icons.help_outline_rounded, size: 16, semanticLabel: 'About this source'),
          ),
        ],
      ),
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
