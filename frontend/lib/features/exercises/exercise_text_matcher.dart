import '../../models/exercise.dart';

const _numberWords = {
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
  'twenty': 20,
};

/// The number a spoken/typed word stands for ("3", "3.", "3)", "three"), or
/// null if it is not one.
int? _numberOf(String word) {
  final cleaned = word.toLowerCase().replaceAll(RegExp(r'^[^a-z0-9]+|[^a-z0-9]+$'), '');
  return int.tryParse(cleaned) ?? _numberWords[cleaned];
}

/// Splits dictated or typed text into one chunk per exercise.
///
/// Numbered lists are the reliable form: "1 reverse lunges 2 bench press 3
/// pull ups" (digits or number words) splits wherever the *next expected*
/// number appears. Only the expected number counts, so a number that is part
/// of an exercise name ("one arm dumbbell row", "21s") does not cut it in two.
///
/// A "1" at the start of a later line begins a new run, so dictating again
/// below an earlier list adds to it.
///
/// Without a leading "1" the text is split on new lines, commas, semicolons
/// and the words "and", "then" and "next".
List<String> splitExerciseList(String text) {
  final lines = [
    for (final line in text.split('\n'))
      line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList(),
  ].where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return const [];

  final chunks = <List<String>>[];
  if (_numberOf(lines.first.first) == 1) {
    var expected = 1;
    for (final line in lines) {
      // A "1" opening a new line starts a new numbered run: a second dictation
      // appended below the first counts from one again.
      if (_numberOf(line.first) == 1) expected = 1;
      for (final word in line) {
        if (_numberOf(word) == expected) {
          chunks.add([]);
          expected++;
        } else {
          chunks.last.add(word);
        }
      }
    }
  } else {
    final parts = text.split(
      RegExp(r'[\n,;]+|\s+(?:and then|then|and|next)\s+', caseSensitive: false),
    );
    chunks.addAll(parts.map((p) => p.split(RegExp(r'\s+'))));
  }

  return [
    for (final chunk in chunks)
      chunk
          .join(' ')
          .replaceAll(RegExp(r'^[\s,;.:\-]+|[\s,;.:\-]+$'), '')
          .replaceAll(RegExp(r'\s+(and|then|next)$', caseSensitive: false), '')
          .trim(),
  ].where((c) => c.isNotEmpty).toList();
}

/// How sure [ExerciseMatcher] is about a [ExerciseMatch].
enum MatchQuality {
  /// Every word matched and the name has nothing extra: "bench press" for
  /// "Bench Press".
  exact,

  /// Every word you said is in the name, but the name has more words or other
  /// exercises fit equally well: "reverse lunges" for "Crossover Reverse Lunge".
  guess,

  /// Only some of the words matched, so [ExerciseMatch.exercise] is a
  /// suggestion at best.
  weak,

  /// Nothing in the catalog looks like it.
  none,
}

class ExerciseMatch {
  const ExerciseMatch({
    required this.query,
    required this.quality,
    this.exercise,
    this.alternatives = const [],
  });

  /// What was said or typed for this exercise.
  final String query;
  final MatchQuality quality;

  /// The best candidate; null only for [MatchQuality.none].
  final Exercise? exercise;

  /// Other close candidates, best first.
  final List<Exercise> alternatives;
}

/// Matches free-form exercise names ("reverse lunges") to the catalog.
///
/// Word order, case, plural endings and punctuation do not matter, a missing
/// word costs less than a wrong one, "db"/"bb" stand for dumbbell/barbell, and
/// a one-letter slip in a longer word (a speech recogniser's usual mistake) is
/// forgiven.
class ExerciseMatcher {
  ExerciseMatcher(List<Exercise> exercises, {this.usage = const {}})
    : _entries = [
        for (var i = 0; i < exercises.length; i++)
          _Entry(exercises[i], i, _tokens(exercises[i].name)),
      ];

  /// Times each exercise id was logged: breaks ties in favour of what the
  /// person actually does.
  final Map<int, int> usage;
  final List<_Entry> _entries;

  ExerciseMatch match(String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return ExerciseMatch(query: query, quality: MatchQuality.none);

    final scored = <_Scored>[];
    for (final entry in _entries) {
      final result = _score(tokens, entry);
      if (result != null) scored.add(result);
    }
    if (scored.isEmpty) return ExerciseMatch(query: query, quality: MatchQuality.none);

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byUse = (usage[b.entry.exercise.id] ?? 0).compareTo(usage[a.entry.exercise.id] ?? 0);
      return byUse != 0 ? byUse : a.entry.index.compareTo(b.entry.index);
    });

    final best = scored.first;
    final MatchQuality quality;
    if (best.coverage < 1) {
      quality = MatchQuality.weak;
    } else if (best.extra == 0) {
      quality = MatchQuality.exact;
    } else {
      quality = MatchQuality.guess;
    }
    return ExerciseMatch(
      query: query,
      quality: quality,
      exercise: best.entry.exercise,
      alternatives: [for (final s in scored.skip(1).take(4)) s.entry.exercise],
    );
  }

  _Scored? _score(List<String> query, _Entry entry) {
    final name = entry.tokens;
    final unused = [...name];
    var matched = 0;
    for (final word in query) {
      final at = unused.indexWhere((n) => _wordsMatch(word, n));
      if (at >= 0) {
        unused.removeAt(at);
        matched++;
      }
    }
    // "pull ups" for "Pullup": same letters, different spacing.
    final sameLetters = query.join() == name.join();
    if (matched == 0 && !sameLetters) return null;

    final coverage = sameLetters ? 1.0 : matched / query.length;
    if (coverage < 0.5) return null;
    final extra = sameLetters ? 0 : name.length - matched;
    return _Scored(entry, coverage, extra, coverage * 10 - extra * 0.5);
  }
}

class _Entry {
  _Entry(this.exercise, this.index, this.tokens);
  final Exercise exercise;
  final int index;
  final List<String> tokens;
}

class _Scored {
  _Scored(this.entry, this.coverage, this.extra, this.score);
  final _Entry entry;
  final double coverage;
  final int extra;
  final double score;
}

const _stopWords = {'a', 'an', 'the', 'of', 'with', 'on', 'exercise', 'exercises'};
const _abbreviations = {'db': 'dumbbell', 'dbs': 'dumbbell', 'bb': 'barbell', 'kb': 'kettlebell'};

List<String> _tokens(String text) {
  return [
    for (final raw in text.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
      if (raw.isNotEmpty && !_stopWords.contains(raw)) _stem(_abbreviations[raw] ?? raw),
  ];
}

/// Drops a plural "s" ("lunges" -> "lunge"); [_wordsMatch] forgives the
/// leftovers ("presses" -> "presse" still starts with "press").
String _stem(String word) => word.length > 2 && word.endsWith('s') && !word.endsWith('ss')
    ? word.substring(0, word.length - 1)
    : word;

bool _wordsMatch(String a, String b) {
  if (a == b) return true;
  final shortest = a.length < b.length ? a.length : b.length;
  // One a prefix of the other covers leftover plural endings ("presse" for
  // "press"); a longer tail is a different word ("over" is not "overhead").
  final longest = a.length > b.length ? a.length : b.length;
  if (shortest >= 4 && longest - shortest <= 2 && (a.startsWith(b) || b.startsWith(a))) {
    return true;
  }
  if (shortest >= 5) {
    final allowed = shortest >= 8 ? 2 : 1;
    return _editDistance(a, b, allowed) <= allowed;
  }
  return false;
}

/// Levenshtein distance, giving up (returning more than [limit]) early.
int _editDistance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous.last;
}
