import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A plain column chart: one bar per entry of [values], scaled to the
/// largest, with [labels] underneath and each non-zero value above its bar.
/// Drawn from widgets rather than a charting package -- the app's other
/// charts are hand-rolled the same way, and these are only ever a dozen bars.
class VerticalBarChart extends StatelessWidget {
  const VerticalBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.highlightIndex,
    this.height = 120,
    this.semanticsLabel,
  }) : assert(values.length == labels.length);

  final List<int> values;

  /// One per value; an empty string leaves that bar unlabelled.
  final List<String> labels;

  /// A bar drawn in the accent colour (e.g. the current week); the rest are
  /// muted.
  final int? highlightIndex;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maxValue = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        excluding: semanticsLabel != null,
        child: SizedBox(
          height: height + 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(values[i] > 0 ? '${values[i]}' : '', style: textTheme.labelSmall),
                        const SizedBox(height: 2),
                        Container(
                          height: maxValue == 0
                              ? 2
                              : (height * values[i] / maxValue).clamp(2, height),
                          decoration: BoxDecoration(
                            color: values[i] == 0
                                ? scheme.surfaceContainerHighest
                                : (i == highlightIndex
                                      ? scheme.primary
                                      : scheme.primary.withValues(alpha: 0.55)),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 16,
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            softWrap: false,
                            style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of a [HorizontalBarList].
class BarRow {
  const BarRow({required this.label, required this.value, required this.valueLabel, this.caption});

  final String label;
  final double value;

  /// Shown at the end of the bar, e.g. "12 sets".
  final String valueLabel;

  /// Optional smaller line under the label.
  final String? caption;
}

/// A ranked list of horizontal bars, scaled to the largest value.
class HorizontalBarList extends StatelessWidget {
  const HorizontalBarList({super.key, required this.rows});

  final List<BarRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maxValue = rows.isEmpty ? 0.0 : rows.map((r) => r.value).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(row.valueLabel, style: textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: LinearProgressIndicator(
                    value: maxValue == 0 ? 0 : row.value / maxValue,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: scheme.primary,
                  ),
                ),
                if (row.caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      row.caption!,
                      style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A big number with a caption -- the building block of the stat grids.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(label, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
