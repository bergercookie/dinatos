import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A plain line chart of [values] in the order given, with a faint grid, the
/// y range labelled at the top and bottom, [startLabel]/[endLabel] under the
/// ends, and the largest value's point drawn in the accent colour. Painted
/// directly -- like [VerticalBarChart], this app's charts are hand-rolled
/// rather than pulling in a charting package for one or two simple plots.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.values,
    required this.formatValue,
    this.startLabel = '',
    this.endLabel = '',
    this.height = 160,
    this.semanticsLabel,
  });

  final List<double> values;

  /// How the y-axis extremes are written, e.g. `(v) => '${v.round()} kg'`.
  final String Function(double value) formatValue;
  final String startLabel;
  final String endLabel;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final minValue = values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        excluding: semanticsLabel != null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LineChartPainter(
                        values: values,
                        line: scheme.primary,
                        grid: scheme.outlineVariant,
                        highlight: scheme.tertiary,
                        surface: scheme.surface,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Text(formatValue(maxValue), style: labelStyle),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: Text(formatValue(minValue), style: labelStyle),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(startLabel, style: labelStyle),
                Text(endLabel, style: labelStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.line,
    required this.grid,
    required this.highlight,
    required this.surface,
  });

  final List<double> values;
  final Color line;
  final Color grid;
  final Color highlight;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // Room above and below so the extreme points and the labels don't clash.
    const padTop = 18.0;
    const padBottom = 18.0;
    final plotHeight = size.height - padTop - padBottom;
    for (var i = 0; i < 3; i++) {
      final y = padTop + plotHeight * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.isEmpty) return;

    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;
    double yFor(double v) =>
        range == 0 ? padTop + plotHeight / 2 : padTop + plotHeight * (1 - (v - minValue) / range);
    double xFor(int i) =>
        values.length == 1 ? size.width / 2 : 8 + (size.width - 16) * i / (values.length - 1);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(xFor(i), yFor(values[i]));
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final bestIndex = values.indexOf(maxValue);
    for (var i = 0; i < values.length; i++) {
      final center = Offset(xFor(i), yFor(values[i]));
      final isBest = i == bestIndex;
      canvas.drawCircle(center, isBest ? 5 : 3.5, Paint()..color = isBest ? highlight : line);
      if (isBest) {
        canvas.drawCircle(
          center,
          5,
          Paint()
            ..color = surface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values ||
      old.line != line ||
      old.grid != grid ||
      old.highlight != highlight ||
      old.surface != surface;
}
