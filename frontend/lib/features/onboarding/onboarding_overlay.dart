import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/design_tokens.dart';
import 'onboarding_controller.dart';
import 'onboarding_steps.dart';

/// Marks a widget as something the first-run tour can point at.
///
/// Wraps nothing visible and handles no input: the tour never puts its own
/// button over a control, so the highlighted thing is the real control and
/// pressing it just does its normal job (the tour notices by where the app
/// goes, or by an event, not by watching presses).
class OnboardingTarget extends ConsumerStatefulWidget {
  const OnboardingTarget({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  ConsumerState<OnboardingTarget> createState() => _OnboardingTargetState();
}

class _OnboardingTargetState extends ConsumerState<OnboardingTarget> implements TourTargetHandle {
  late final TourTargetRegistry _registry = ref.read(tourTargetRegistryProvider);
  bool _showing = true;

  @override
  bool get isShowing => _showing;

  @override
  void initState() {
    super.initState();
    _registry.register(widget.id, this);
  }

  @override
  void didUpdateWidget(OnboardingTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _registry.unregister(oldWidget.id, this);
      _registry.register(widget.id, this);
    }
  }

  @override
  void dispose() {
    _registry.unregister(widget.id, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _showing = TickerMode.valuesOf(context).enabled;
    return widget.child;
  }
}

/// Wraps the app (as `MaterialApp.router`'s `builder`) with the first-run
/// tour: starts it for an account that hasn't seen it, draws the dimmed
/// spotlight and instruction card above whatever screen is showing, and
/// feeds navigation back to the controller so steps can complete by the
/// user simply using the app.
class OnboardingOverlay extends ConsumerStatefulWidget {
  const OnboardingOverlay({super.key, required this.child, required this.router});

  final Widget child;
  final GoRouter router;

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay>
    with SingleTickerProviderStateMixin {
  /// A target is highlighted a little larger than it is, so the ring isn't
  /// flush against its edges.
  static const double _padding = 6;
  static const double _cardWidth = 340;
  static const double _cardMargin = 16;

  /// Roughly how tall the card is -- only used to choose whether it fits
  /// above or below the target, never to size it.
  static const double _cardHeight = 200;

  late final Ticker _ticker = createTicker((_) => _syncTarget());
  Rect? _targetRect;
  String? _scrolledForStep;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onLocationChanged);
    final auth = ref.read(authNotifierProvider);
    if (auth is AuthAuthenticated) _signedIn(auth);
  }

  @override
  void didUpdateWidget(OnboardingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_onLocationChanged);
      widget.router.routerDelegate.addListener(_onLocationChanged);
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onLocationChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _signedIn(AuthAuthenticated auth) {
    // Not synchronously: this can run during a build.
    Future.microtask(() {
      if (mounted) ref.read(onboardingProvider.notifier).userSignedIn(auth.user.id);
    });
  }

  void _onLocationChanged() {
    final path = widget.router.routerDelegate.currentConfiguration.uri.path;
    Future.microtask(() {
      if (mounted) ref.read(onboardingProvider.notifier).locationChanged(path);
    });
  }

  /// Re-measures the highlighted target every frame while a tour is
  /// running: it can move under us (a list scrolling, a tab switching, a
  /// sheet closing) with no notification to hook.
  void _syncTarget() {
    final controller = ref.read(onboardingProvider.notifier);
    final target = controller.currentStep?.target;
    Rect? rect;
    if (target != null) {
      rect = ref
          .read(tourTargetRegistryProvider)
          .boundsOf(
            target,
            onFound: (context, rect) => _scrollIntoView(controller.currentStep!.id, context, rect),
          );
    }
    if (rect != _targetRect) setState(() => _targetRect = rect);
  }

  /// Brings a target that is (partly) scrolled out of view back on screen,
  /// once per step -- repeating it would fight the user's own scrolling.
  void _scrollIntoView(String stepId, BuildContext targetContext, Rect rect) {
    if (_scrolledForStep == stepId) return;
    _scrolledForStep = stepId;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    if (screen.contains(rect.topLeft) && screen.contains(rect.bottomRight)) return;
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.4,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authNotifierProvider, (_, next) {
      if (next is AuthAuthenticated) {
        _signedIn(next);
      } else if (next is AuthUnauthenticated) {
        ref.read(onboardingProvider.notifier).userSignedOut();
      }
    });
    final state = ref.watch(onboardingProvider);
    final step = ref.read(onboardingProvider.notifier).currentStep;

    if (step == null) {
      if (_ticker.isActive) _ticker.stop();
      _targetRect = null;
      _scrolledForStep = null;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }

    return Stack(
      children: [
        widget.child,
        if (step != null)
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: _TourLayer(
                key: ValueKey(step.id),
                step: step,
                index: state.stepIndex!,
                total: ref.read(tourStepsProvider).length,
                targetRect: _targetRect?.inflate(_padding),
                cardWidth: _cardWidth,
                cardMargin: _cardMargin,
                cardHeight: _cardHeight,
              ),
            ),
          ),
      ],
    );
  }
}

class _TourLayer extends ConsumerWidget {
  const _TourLayer({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.targetRect,
    required this.cardWidth,
    required this.cardMargin,
    required this.cardHeight,
  });

  final TourStep step;
  final int index;
  final int total;
  final Rect? targetRect;
  final double cardWidth;
  final double cardMargin;
  final double cardHeight;

  static const Color _dim = Color(0x99000000);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(onboardingProvider.notifier);
    final rect = targetRect;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final width = (size.width - 2 * cardMargin).clamp(0.0, cardWidth);

        // A card with nothing to point at is a plain dialog: dim and block everything.
        final blockEverything = step.target == null;
        // A modal step blocks everything *except* the spotlighted hole, so
        // the only thing left to press is the one the step is about -- but
        // only once that target has actually been found, or a step whose
        // target isn't on screen would lock the whole app.
        final blockAroundHole = step.modal && rect != null;

        double? top;
        double? bottom;
        var left = (size.width - width) / 2;
        if (rect == null) {
          bottom = cardMargin + 72; // clear of the bottom nav bar
          if (blockEverything) {
            top = null;
            bottom = null;
          }
        } else {
          left = (rect.center.dx - width / 2).clamp(cardMargin, size.width - width - cardMargin);
          final below = size.height - rect.bottom;
          final above = rect.top;
          if (step.cardPlacement == CardPlacement.screenBottom) {
            bottom = cardMargin + 72;
          } else if (step.cardPlacement == CardPlacement.screenTop) {
            top = cardMargin + 56;
          } else if (below >= cardHeight + cardMargin) {
            top = rect.bottom + cardMargin;
          } else if (above >= cardHeight + cardMargin) {
            bottom = size.height - rect.top + cardMargin;
          } else if (rect.center.dy < size.height / 2) {
            bottom = cardMargin + 72;
          } else {
            top = cardMargin + 56;
          }
        }

        final card = SizedBox(
          width: width,
          child: _TourCard(
            step: step,
            index: index,
            total: total,
            onPrimary: controller.next,
            onSkipStep: controller.next,
            onSkipTour: controller.finish,
            scheme: scheme,
          ),
        );

        return Stack(
          children: [
            if (blockEverything)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const ColoredBox(color: _dim),
                ),
              )
            else if (rect != null) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SpotlightPainter(
                      rect: rect,
                      dim: step.modal ? _dim : Colors.transparent,
                      ring: scheme.primary,
                    ),
                  ),
                ),
              ),
              if (blockAroundHole) ..._blockersAround(rect, size),
            ],
            if (blockEverything)
              Center(child: card)
            else
              Positioned(top: top, bottom: bottom, left: left, child: card),
          ],
        );
      },
    );
  }

  /// Four opaque rectangles tiling everything but [hole], absorbing taps.
  List<Widget> _blockersAround(Rect hole, Size size) {
    Widget block(Rect r) => Positioned.fromRect(
      rect: r,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}),
    );
    return [
      block(Rect.fromLTRB(0, 0, size.width, hole.top)),
      block(Rect.fromLTRB(0, hole.bottom, size.width, size.height)),
      block(Rect.fromLTRB(0, hole.top, hole.left, hole.bottom)),
      block(Rect.fromLTRB(hole.right, hole.top, size.width, hole.bottom)),
    ];
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.rect, required this.dim, required this.ring});

  final Rect rect;
  final Color dim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(rect, const Radius.circular(AppRadius.sm));
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(scrim, Paint()..color = dim);
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.rect != rect || old.dim != dim || old.ring != ring;
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.index,
    required this.total,
    required this.onPrimary,
    required this.onSkipStep,
    required this.onSkipTour,
    required this.scheme,
  });

  final TourStep step;
  final int index;
  final int total;
  final VoidCallback onPrimary;
  final VoidCallback onSkipStep;
  final VoidCallback onSkipTour;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isLast = index == total - 1;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Tour step ${index + 1} of $total: ${step.title}',
      child: Card(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOUR · ${index + 1} OF $total',
                style: textTheme.labelSmall?.copyWith(color: scheme.primary, letterSpacing: 1),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(step.title, style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(step.body, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.md),
              // A Wrap, not a Row: with a large system font or a narrow phone
              // the two buttons drop onto separate lines rather than overflow.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (!isLast)
                      TextButton(onPressed: onSkipTour, child: const Text('Skip tour'))
                    else
                      const SizedBox.shrink(),
                    if (step.primaryLabel == null)
                      TextButton(onPressed: onSkipStep, child: const Text('Skip step'))
                    else
                      FilledButton(onPressed: onPrimary, child: Text(step.primaryLabel!)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
