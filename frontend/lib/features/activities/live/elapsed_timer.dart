import 'dart:async';

import 'package:flutter/material.dart';

/// A ticking "h:mm:ss since [since]" (or "since [since] until [until]" for a
/// fixed span) -- isolated in its own `StatefulWidget` with its own
/// `Timer.periodic` so the one-second tick only rebuilds this small text,
/// not the whole live workout screen around it.
class ElapsedTimer extends StatefulWidget {
  const ElapsedTimer({super.key, required this.since, this.until, this.style});

  final DateTime since;

  /// A fixed end to measure against instead of "now" -- used on the summary
  /// screen, where the duration shown must stay the workout's actual length
  /// and not keep climbing after it's over.
  final DateTime? until;
  final TextStyle? style;

  @override
  State<ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<ElapsedTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(ElapsedTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `until` flipping between null and a value (a stopwatch being paused
    // or resumed) must start/stop the tick, not just change what build() reads.
    _syncTimer();
  }

  void _syncTimer() {
    if (widget.until == null) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = (widget.until ?? DateTime.now()).difference(widget.since);
    return Text(formatElapsed(elapsed), style: widget.style);
  }
}

String formatElapsed(Duration elapsed) {
  final clamped = elapsed.isNegative ? Duration.zero : elapsed;
  final hours = clamped.inHours;
  final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Parses what a person types to set the stopwatch: `h:mm:ss`, `m:ss`, or a
/// bare number of minutes. Returns null for anything else (empty, negative,
/// seconds/minutes >= 60 in a multi-part form, non-numeric).
Duration? parseElapsed(String input) {
  final parts = input.trim().split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part.trim());
    if (n == null || n < 0) return null;
    numbers.add(n);
  }
  if (numbers.length == 1) return Duration(minutes: numbers[0]);
  if (numbers.skip(1).any((n) => n >= 60)) return null;
  if (numbers.length == 2) return Duration(minutes: numbers[0], seconds: numbers[1]);
  return Duration(hours: numbers[0], minutes: numbers[1], seconds: numbers[2]);
}
