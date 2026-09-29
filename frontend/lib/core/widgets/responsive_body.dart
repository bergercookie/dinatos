import 'package:flutter/material.dart';

/// Caps a screen body's width and centers it on wide viewports (a desktop
/// browser window) -- without this, every list, form and button stretches
/// edge-to-edge the way it should only do on a phone-width screen.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
