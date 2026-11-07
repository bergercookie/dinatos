import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/design_tokens.dart';
import '../activities/live/start_routine_workout.dart';
import 'routines_repository.dart';

/// Where a routine's home-screen shortcut lands: loads the routine and starts
/// a live workout from it straight away -- through the same flow as the play
/// button, so a workout already under way is never silently discarded.
/// Shows why not when it cannot (for example the routine was deleted after the
/// shortcut was pinned).
class StartRoutineScreen extends ConsumerStatefulWidget {
  const StartRoutineScreen({super.key, required this.routineId});

  final int routineId;

  @override
  ConsumerState<StartRoutineScreen> createState() => _StartRoutineScreenState();
}

class _StartRoutineScreenState extends ConsumerState<StartRoutineScreen> {
  String? _error;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _gone = false;
    });
    try {
      final routine = await ref.read(routinesRepositoryProvider).get(widget.routineId);
      if (!mounted) return;
      final started = await startWorkoutFromRoutine(context, ref, routine);
      // Dismissing the "already in progress" dialog starts nothing: do not
      // leave the person on a spinner. (When it did navigate, this screen is
      // being replaced, so go only on `false`.)
      if (!started && mounted) context.go('/routines');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _gone = error.isNotFound;
        _error = error.isNotFound
            ? 'This routine no longer exists. It may have been deleted.'
            : 'Could not start the workout: ${error.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Starting workout')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    if (!_gone) FilledButton(onPressed: _start, child: const Text('Try again')),
                    TextButton(
                      onPressed: () => context.go('/routines'),
                      child: const Text('Back to Routines'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
