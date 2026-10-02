import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';

const _maxAxes = 6;

/// A spider/radar chart of muscle emphasis: one axis per muscle group,
/// sized by accumulated volume (see `muscle_volume.dart`). Capped at
/// [_maxAxes] axes (the heaviest-worked muscles so far) -- a radar chart
/// with a dozen cramped spokes reads as noise, not signal.
///
/// Fewer than 3 muscles logged can't make a meaningful polygon (two points
/// and a center are just a line), so that case falls back to a simple
/// ranked bar list instead of drawing a degenerate "radar".
class MuscleRadarChart extends StatelessWidget {
  const MuscleRadarChart({super.key, required this.volumes});

  /// Muscle name -> accumulated volume. Values are relative to each other,
  /// not an absolute unit the chart displays.
  final Map<String, double> volumes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (volumes.isEmpty) {
      return Center(
        child: Text(
          'Log a set to see which muscles you\'re working',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final sorted = volumes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(_maxAxes).toList();

    if (top.length < 3) {
      return _MuscleBarList(entries: top);
    }

    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _RadarPainter(
          entries: top,
          gridColor: scheme.outlineVariant,
          labelColor: scheme.onSurfaceVariant,
          fillColor: scheme.primary.withValues(alpha: 0.25),
          strokeColor: scheme.primary,
        ),
        child: Container(),
      ),
    );
  }
}

class _MuscleBarList extends StatelessWidget {
  const _MuscleBarList({required this.entries});

  final List<MapEntry<String, double>> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = entries.map((e) => e.value).reduce(math.max);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(_titleCase(entry.key), style: Theme.of(context).textTheme.bodySmall),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: LinearProgressIndicator(
                      value: maxValue == 0 ? 0 : entry.value / maxValue,
                      minHeight: 10,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.entries,
    required this.gridColor,
    required this.labelColor,
    required this.fillColor,
    required this.strokeColor,
  });

  final List<MapEntry<String, double>> entries;
  final Color gridColor;
  final Color labelColor;
  final Color fillColor;
  final Color strokeColor;

  static const _ringCount = 4;
  static const _labelReserve = 36.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - _labelReserve;
    if (radius <= 0) return;
    final axisCount = entries.length;
    final maxValue = entries.map((e) => e.value).reduce(math.max);

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Concentric rings.
    for (var ring = 1; ring <= _ringCount; ring++) {
      final ringRadius = radius * ring / _ringCount;
      final path = Path();
      for (var i = 0; i < axisCount; i++) {
        final point = _axisPoint(center, ringRadius, i, axisCount);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Spokes + labels.
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < axisCount; i++) {
      final outer = _axisPoint(center, radius, i, axisCount);
      canvas.drawLine(center, outer, gridPaint);

      final labelPoint = _axisPoint(center, radius + 16, i, axisCount);
      textPainter.text = TextSpan(
        text: _titleCase(entries[i].key),
        style: TextStyle(color: labelColor, fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(labelPoint.dx - textPainter.width / 2, labelPoint.dy - textPainter.height / 2),
      );
    }

    // Data polygon.
    final dataPath = Path();
    for (var i = 0; i < axisCount; i++) {
      final value = entries[i].value;
      final ratio = maxValue == 0 ? 0.0 : value / maxValue;
      final point = _axisPoint(center, radius * ratio, i, axisCount);
      if (i == 0) {
        dataPath.moveTo(point.dx, point.dy);
      } else {
        dataPath.lineTo(point.dx, point.dy);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, Paint()..color = fillColor);
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  Offset _axisPoint(Offset center, double radius, int index, int count) {
    final angle = (2 * math.pi * index / count) - math.pi / 2;
    return Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.entries != entries ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor;
  }
}

String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
