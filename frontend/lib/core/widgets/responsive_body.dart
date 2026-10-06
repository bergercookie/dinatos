import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Caps a screen body's width and centers it on wide viewports (a desktop
/// browser window) -- without this, every list, form and button stretches
/// edge-to-edge the way it should only do on a phone-width screen.
///
/// The mouse wheel still scrolls the body from anywhere in the window: the
/// capped column is all a scroll view inside it can see, so a wheel turned in
/// the empty margins beside it would otherwise do nothing.
class ResponsiveBody extends StatefulWidget {
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  State<ResponsiveBody> createState() => _ResponsiveBodyState();
}

class _ResponsiveBodyState extends State<ResponsiveBody> {
  final _contentKey = GlobalKey();

  /// The outermost vertical scroll view inside the capped column, if any.
  ScrollPosition? _findVerticalScroll() {
    final root = _contentKey.currentContext;
    if (root == null) return null;
    ScrollPosition? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (position.axis == Axis.vertical && position.hasContentDimensions) {
          found = position;
          return;
        }
      }
      element.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return found;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final box = _contentKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // Over the column itself, its own scroll view already handles it.
    if (box.paintBounds.contains(box.globalToLocal(event.position))) return;
    _findVerticalScroll()?.pointerScroll(event.scrollDelta.dy);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onPointerSignal,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: KeyedSubtree(key: _contentKey, child: widget.child),
        ),
      ),
    );
  }
}
