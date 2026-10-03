import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../progress/progression.dart' show formatKg;

/// The bar most barbell lifts use.
const defaultBarKg = 20.0;

/// The plates (kg) a gym usually has, heaviest first.
const standardPlatesKg = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];

/// How to load a barbell to a target weight.
class PlateLoad {
  const PlateLoad({required this.perSide, required this.loadedKg, required this.shortKg});

  /// The plates to put on *each* side, heaviest first (empty: just the bar).
  final List<double> perSide;

  /// What the bar weighs with those plates on it, both sides.
  final double loadedKg;

  /// How far [loadedKg] falls short of the target -- 0 when it's exact; more
  /// than 0 when the target isn't reachable with these plates.
  final double shortKg;

  bool get isExact => shortKg == 0;
}

/// The plates for [targetKg] on a [barKg] bar, taking the heaviest plate that
/// fits at each step. Null when the target is below the bar itself.
///
/// Works in hundredths of a kilo so 1.25 kg plates don't pick up
/// floating-point error.
PlateLoad? platesFor(
  double targetKg, {
  double barKg = defaultBarKg,
  List<double> plates = standardPlatesKg,
}) {
  int hundredths(double kg) => (kg * 100).round();
  final target = hundredths(targetKg);
  final bar = hundredths(barKg);
  if (target < bar) return null;
  var perSideLeft = (target - bar) ~/ 2;
  final used = <double>[];
  for (final plate in [...plates]..sort((a, b) => b.compareTo(a))) {
    final size = hundredths(plate);
    while (size > 0 && perSideLeft >= size) {
      used.add(plate);
      perSideLeft -= size;
    }
  }
  final loaded = bar + 2 * used.fold<int>(0, (sum, p) => sum + hundredths(p));
  return PlateLoad(perSide: used, loadedKg: loaded / 100, shortKg: (target - loaded) / 100);
}

/// "25 + 10 + 2.5", or "no plates" for an empty bar.
String describePlates(List<double> plates) =>
    plates.isEmpty ? 'no plates' : plates.map(formatKg).join(' + ');

/// A dialog that works out which plates to load for [targetKg] (or whatever
/// is typed into it).
Future<void> showPlateCalculator(BuildContext context, {double? targetKg}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PlateCalculatorDialog(initialTargetKg: targetKg),
  );
}

class _PlateCalculatorDialog extends StatefulWidget {
  const _PlateCalculatorDialog({this.initialTargetKg});

  final double? initialTargetKg;

  @override
  State<_PlateCalculatorDialog> createState() => _PlateCalculatorDialogState();
}

class _PlateCalculatorDialogState extends State<_PlateCalculatorDialog> {
  late final _targetController = TextEditingController(
    text: widget.initialTargetKg == null ? '' : formatKg(widget.initialTargetKg!),
  );
  final _barController = TextEditingController(text: formatKg(defaultBarKg));

  @override
  void dispose() {
    _targetController.dispose();
    _barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = double.tryParse(_targetController.text);
    final bar = double.tryParse(_barController.text);
    final load = target == null || bar == null ? null : platesFor(target, barKg: bar);
    final scheme = Theme.of(context).colorScheme;

    Widget result;
    if (target == null || bar == null) {
      result = Text('Enter the weight to load.', style: TextStyle(color: scheme.onSurfaceVariant));
    } else if (load == null) {
      result = Text(
        'That is lighter than the bar.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    } else {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Each side', style: Theme.of(context).textTheme.labelMedium),
          Text(describePlates(load.perSide), style: Theme.of(context).textTheme.titleLarge),
          if (!load.isExact) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Closest with these plates: ${formatKg(load.loadedKg)} kg '
              '(${formatKg(load.shortKg)} kg short).',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      );
    }

    return AlertDialog(
      title: const Text('Plate calculator'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _targetController,
            autofocus: widget.initialTargetKg == null,
            decoration: const InputDecoration(labelText: 'Weight to load (kg)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _barController,
            decoration: const InputDecoration(labelText: 'Bar (kg)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          result,
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
