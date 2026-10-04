import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One polygon on a [RadarChart]: a value from 0 to 100 for each axis.
/// A null value leaves that axis out of the polygon's outline, which is drawn
/// through the known axes only.
class RadarSeries {
  const RadarSeries({required this.name, required this.values, required this.color});

  final String name;
  final List<double?> values;
  final Color color;
}

/// A spider/radar chart: one spoke per entry of [labels], concentric rings at
/// 25/50/75/100, and a filled polygon per series. Painted directly, like the
/// app's other charts, rather than pulling in a charting package.
class RadarChart extends StatelessWidget {
  const RadarChart({
    super.key,
    required this.labels,
    required this.series,
    this.size = 320,
    this.semanticsLabel,
  }) : assert(labels.length >= 3);

  final List<String> labels;
  final List<RadarSeries> series;

  /// The side of the (square) chart, labels included.
  final double size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle =
        Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurface) ??
        const TextStyle(fontSize: 12);
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        excluding: semanticsLabel != null,
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: size, maxHeight: size),
              child: CustomPaint(
                painter: _RadarPainter(
                  labels: labels,
                  series: series,
                  gridColor: scheme.outlineVariant,
                  labelStyle: labelStyle,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.labels,
    required this.series,
    required this.gridColor,
    required this.labelStyle,
    required this.textDirection,
  });

  final List<String> labels;
  final List<RadarSeries> series;
  final Color gridColor;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  static const _rings = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final center = size.center(Offset.zero);
    // Leave room around the web for the axis labels.
    final labelMargin = math.min(size.width * 0.2, 64.0);
    final radius = size.shortestSide / 2 - labelMargin;
    if (radius <= 0) return;

    // Spokes start at the top and go clockwise.
    Offset point(int i, double fraction) {
      final angle = -math.pi / 2 + 2 * math.pi * i / n;
      return center + Offset(math.cos(angle), math.sin(angle)) * (radius * fraction);
    }

    final grid = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var ring = 1; ring <= _rings; ring++) {
      final path = Path()..moveTo(point(0, ring / _rings).dx, point(0, ring / _rings).dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(point(i, ring / _rings).dx, point(i, ring / _rings).dy);
      }
      canvas.drawPath(path..close(), grid);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, point(i, 1), grid);
    }

    for (final s in series) {
      final known = [
        for (var i = 0; i < n; i++)
          if (i < s.values.length && s.values[i] != null) i,
      ];
      if (known.isEmpty) continue;
      Offset at(int i) => point(i, (s.values[i]! / 100).clamp(0.0, 1.0));
      final path = Path()..moveTo(at(known.first).dx, at(known.first).dy);
      for (final i in known.skip(1)) {
        path.lineTo(at(i).dx, at(i).dy);
      }
      if (known.length > 2) path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
      for (final i in known) {
        canvas.drawCircle(at(i), 3.5, Paint()..color = s.color);
      }
    }

    for (var i = 0; i < n; i++) {
      final painter = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textAlign: TextAlign.center,
        textDirection: textDirection,
        maxLines: 2,
      )..layout(maxWidth: labelMargin * 2);
      final anchor = point(i, 1.0) + (point(i, 1.0) - center) / radius * 14;
      // Centre the label on its anchor, then nudge it clear of the web along
      // the spoke's direction so top/bottom labels don't sit on the polygon.
      final dx = (anchor.dx - center.dx) / radius;
      final dy = (anchor.dy - center.dy) / radius;
      final offset =
          anchor -
          Offset(painter.width / 2, painter.height / 2) +
          Offset(dx * painter.width / 2, dy * painter.height / 2);
      // Keep a wide label (a long persona name on a side spoke) on the canvas.
      painter.paint(
        canvas,
        Offset(
          offset.dx.clamp(0.0, math.max(0.0, size.width - painter.width)),
          offset.dy.clamp(0.0, math.max(0.0, size.height - painter.height)),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.labels != labels ||
      old.series != series ||
      old.gridColor != gridColor ||
      old.labelStyle != labelStyle;
}
