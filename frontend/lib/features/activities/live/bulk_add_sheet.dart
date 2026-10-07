import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_tokens.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../models/exercise.dart';
import '../../exercises/exercise_picker.dart';
import '../../exercises/exercise_text_matcher.dart';
import '../activities_providers.dart';
import 'speech_input.dart';

/// Opens the "add several exercises" sheet over [exercises] and resolves with
/// the ones the person confirmed, in the order they were named (null if the
/// sheet was dismissed).
///
/// The person dictates (Android) or types a list -- "1 reverse lunges 2 bench
/// press 3 pull ups" -- the text is split into one entry per exercise and each
/// is matched to the catalog (see `exercise_text_matcher.dart`). Nothing is
/// added until they have looked at the matches and pressed the button: speech
/// recognition mishears, and a wrong exercise in a workout under way is worse
/// than one more tap.
Future<List<Exercise>?> showBulkAddSheet(
  BuildContext context, {
  required List<Exercise> exercises,
}) {
  return showModalBottomSheet<List<Exercise>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _BulkAddSheet(exercises: exercises),
  );
}

class _Row {
  _Row(ExerciseMatch match)
    : query = match.query,
      quality = match.quality,
      exercise = match.exercise,
      checked = match.quality == MatchQuality.exact || match.quality == MatchQuality.guess;

  final String query;
  MatchQuality quality;
  Exercise? exercise;
  bool checked;

  /// Whether the person changed this row by hand; such a row survives the
  /// text above it being edited.
  bool edited = false;
}

class _BulkAddSheet extends ConsumerStatefulWidget {
  const _BulkAddSheet({required this.exercises});

  final List<Exercise> exercises;

  @override
  ConsumerState<_BulkAddSheet> createState() => _BulkAddSheetState();
}

class _BulkAddSheetState extends ConsumerState<_BulkAddSheet> {
  final _controller = TextEditingController();
  late final ExerciseMatcher _matcher;
  late final SpeechInput _speech;
  List<_Row> _rows = [];
  bool _listening = false;
  String? _speechError;

  /// What was in the box when listening began: the transcript is appended to
  /// it, so dictating again adds to the list instead of replacing it.
  String _textBeforeListening = '';

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechInputProvider);
    _matcher = ExerciseMatcher(
      widget.exercises,
      usage: ref.read(exerciseUsageProvider).valueOrNull ?? const {},
    );
  }

  @override
  void dispose() {
    if (_listening) {
      // Cleared first: stopping reports back through onDone, which must not
      // setState on a sheet that is going away.
      _listening = false;
      _speech.stop();
    }
    _controller.dispose();
    super.dispose();
  }

  void _reparse() {
    final queries = splitExerciseList(_controller.text);
    final previous = _rows;
    _rows = [
      for (var i = 0; i < queries.length; i++)
        if (i < previous.length && previous[i].edited && previous[i].query == queries[i])
          previous[i]
        else
          _Row(_matcher.match(queries[i])),
    ];
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      return;
    }
    setState(() {
      _speechError = null;
      _listening = true;
      // A new line, so a second dictation counting from "1" again is read as
      // a new run (see splitExerciseList).
      _textBeforeListening = _controller.text.trimRight();
    });
    final error = await _speech.start(
      onText: (text) {
        if (!mounted) return;
        setState(() {
          _controller.text = _textBeforeListening.isEmpty ? text : '$_textBeforeListening\n$text';
          _reparse();
        });
      },
      onDone: () {
        if (mounted && _listening) setState(() => _listening = false);
      },
    );
    if (error != null && mounted) {
      setState(() {
        _listening = false;
        _speechError = error;
      });
    }
  }

  Future<void> _change(_Row row) async {
    final picked = await showExercisePicker(
      context,
      exercises: widget.exercises,
      initialQuery: row.query,
    );
    if (picked == null || !mounted) return;
    setState(() {
      row
        ..exercise = picked
        ..quality = MatchQuality.exact
        ..checked = true
        ..edited = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = [
      for (final row in _rows)
        if (row.checked && row.exercise != null) row.exercise!,
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add several exercises', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _HowItWorks(canSpeak: _speech.isSupported),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _controller,
                      minLines: 2,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Your exercises',
                        hintText: '1 reverse lunges\n2 bench press\n3 pull ups',
                        alignLabelWithHint: true,
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() {
                                  _controller.clear();
                                  _reparse();
                                }),
                              ),
                      ),
                      onChanged: (_) => setState(_reparse),
                    ),
                    if (_speech.isSupported) ...[
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: _toggleListening,
                        icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
                        label: Text(_listening ? 'Stop listening' : 'Tap and speak'),
                        style: _listening
                            ? FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.errorContainer,
                                foregroundColor: theme.colorScheme.onErrorContainer,
                              )
                            : null,
                      ),
                      if (_listening)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            'Listening... say each exercise after its number, '
                            'like "1 bench press, 2 squats".',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                    if (_speechError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      ErrorBanner(message: _speechError!),
                    ],
                    if (_rows.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text('Check what we understood', style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Untick any you do not want. Tap a row to pick a different exercise.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final row in _rows)
                        _MatchTile(
                          row: row,
                          onChecked: (on) => setState(() => row.checked = on),
                          onChange: () => _change(row),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: chosen.isEmpty ? null : () => Navigator.of(context).pop(chosen),
                icon: const Icon(Icons.add),
                label: Text(
                  chosen.isEmpty
                      ? 'Add exercises'
                      : 'Add ${chosen.length} ${chosen.length == 1 ? 'exercise' : 'exercises'}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Sets and reps are not needed now -- fill them in on each exercise afterwards.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The three steps, always on screen, so nobody has to guess what the box is
/// for or what format it wants.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.canSpeak});

  final bool canSpeak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onSecondaryContainer);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            canSpeak
                ? '1. Say or type your exercises, one after another, each starting with '
                      'its number: "1 reverse lunges, 2 bench press, 3 pull ups". '
                      'A part of the name is enough.'
                : '1. Type your exercises, each starting with its number or on its own '
                      'line: "1 reverse lunges, 2 bench press". A part of the name is enough.',
            style: style,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('2. Check the matches that appear below.', style: style),
          const SizedBox(height: AppSpacing.xs),
          Text('3. Tap the button to add them to your workout.', style: style),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.row, required this.onChecked, required this.onChange});

  final _Row row;
  final ValueChanged<bool> onChecked;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color, String status) = switch (row.quality) {
      MatchQuality.exact => (Icons.check_circle_outline, scheme.primary, 'Matched'),
      MatchQuality.guess => (Icons.help_outline, scheme.tertiary, 'Best guess -- please check'),
      MatchQuality.weak => (Icons.warning_amber_rounded, scheme.error, 'Not sure -- tap to choose'),
      MatchQuality.none => (Icons.search_off_rounded, scheme.error, 'No match -- tap to search'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onChange,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Row(
            children: [
              Checkbox(
                value: row.checked,
                // Nothing to add for a row with no exercise yet.
                onChanged: row.exercise == null ? null : (on) => onChecked(on ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.exercise?.name ?? 'No exercise found',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text('You said "${row.query}"', style: theme.textTheme.bodySmall),
                    Row(
                      children: [
                        Icon(icon, size: 14, color: color),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            status,
                            style: theme.textTheme.bodySmall?.copyWith(color: color),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, size: 20),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}
