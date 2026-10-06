import 'dart:async';
import 'dart:convert';

import 'local_document_storage.dart';

/// What the engine answers with; the Dio adapter turns it into a response.
class LocalResponse {
  const LocalResponse(this.status, [this.body, this.headers = const {}]);

  final int status;
  final Object? body;
  final Map<String, String> headers;
}

class _HttpError implements Exception {
  const _HttpError(this.status, this.detail);

  final int status;
  final String detail;
}

typedef CatalogLoader = Future<List<Map<String, dynamic>>> Function();

const _exportFormat = 'dinatos-user-export';
const _firstCustomExerciseId = 100000;

/// The app's own API, answered on the device: the same paths, bodies and
/// status codes as the backend's (see `backend/src/dinatos_backend/api`) for
/// everything the app uses without an account -- exercises, routines,
/// activities, measurements, the profile and the export/import file -- so
/// the repositories and screens are the very same code in both modes.
///
/// Data lives in one JSON document ([LocalDocumentStorage]); the built-in
/// exercise catalog is bundled with the app and never stored, so a custom
/// exercise is the only kind that has to be saved. Not here, by design:
/// accounts, administration, the Hevy import and tutorials -- they answer
/// 404 "needs a server".
class LocalApi {
  LocalApi({
    required this.storage,
    required this.loadCatalog,
    this.appVersion = 'dev',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalDocumentStorage storage;
  final CatalogLoader loadCatalog;
  final String appVersion;
  final DateTime Function() _clock;

  Map<String, dynamic>? _doc;
  List<Map<String, dynamic>> _builtIn = const [];
  Future<void>? _loading;

  // Requests are handled one at a time: each reads and rewrites the one
  // document, and two interleaved writes would lose one of them.
  Future<void> _queue = Future.value();

  Future<LocalResponse> handle(String method, Uri uri, Object? body) {
    final result = _queue.then((_) => _handle(method, uri, body));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<LocalResponse> _handle(String method, Uri uri, Object? body) async {
    try {
      await (_loading ??= _load());
      final before = jsonEncode(_doc);
      final response = _route(method, uri, body);
      final after = jsonEncode(_doc);
      if (after != before) await storage.write(after);
      return response;
    } on _HttpError catch (error) {
      return LocalResponse(error.status, {'detail': error.detail});
    }
  }

  // ---------------------------------------------------------------- loading

  Future<void> _load() async {
    final catalog = await loadCatalog();
    _builtIn = [
      for (var i = 0; i < catalog.length; i++) {...catalog[i], 'id': i + 1, 'is_custom': false},
    ];
    final raw = await storage.read();
    _doc = raw == null ? _emptyDoc() : jsonDecode(raw) as Map<String, dynamic>;
    if (_doc!['seeded'] != true) {
      _seedStarterRoutines();
      _doc!['seeded'] = true;
      await storage.write(jsonEncode(_doc));
    }
  }

  Map<String, dynamic> _emptyDoc() => {
    'version': 1,
    'seeded': false,
    'next_id': {
      'exercise': _firstCustomExerciseId,
      'routine': 1,
      'activity': 1,
      'measurement': 1,
      'row': 1, // routine/activity exercises and sets
    },
    'profile': <String, dynamic>{'height_cm': null, 'unit_system': 'metric'},
    'exercises': <dynamic>[],
    'routines': <dynamic>[],
    'activities': <dynamic>[],
    'measurements': <dynamic>[],
  };

  List<Map<String, dynamic>> _list(String key) =>
      (_doc![key] as List<dynamic>).cast<Map<String, dynamic>>();

  int _nextId(String kind) {
    final ids = _doc!['next_id'] as Map<String, dynamic>;
    final id = ids[kind] as int;
    ids[kind] = id + 1;
    return id;
  }

  // ---------------------------------------------------------------- routing

  LocalResponse _route(String method, Uri uri, Object? body) {
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final query = uri.queryParameters;
    final head = parts.isEmpty ? '' : parts.first;
    final id = parts.length > 1 ? int.tryParse(parts[1]) : null;
    switch (head) {
      case 'auth':
        return _auth(method, parts);
      case 'exercises':
        return _exercises(method, parts, id, query, body);
      case 'routines':
        return _collection('routine', 'routines', method, parts, id, body);
      case 'activities':
        return _activities(method, parts, id, query, body);
      case 'measurements':
        return _collection('measurement', 'measurements', method, parts, id, body);
      case 'profile':
        return _profile(method, parts, query, body);
    }
    throw const _HttpError(404, 'this needs a server -- it is not available in local mode');
  }

  LocalResponse _auth(String method, List<String> parts) {
    final what = parts.length > 1 ? parts[1] : '';
    if (what == 'me' && method == 'GET') {
      return const LocalResponse(200, {'id': 1, 'email': 'this device', 'is_admin': false});
    }
    if (what == 'logout') return const LocalResponse(204);
    if (what == 'config') return const LocalResponse(200, {'registration_enabled': false});
    throw const _HttpError(404, 'there are no accounts in local mode');
  }

  // -------------------------------------------------------------- exercises

  Iterable<Map<String, dynamic>> get _allExercises sync* {
    yield* _builtIn;
    yield* _list('exercises');
  }

  Map<String, dynamic>? _exerciseById(int id) {
    for (final e in _allExercises) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  Map<String, dynamic> _exerciseOr404(int? id) =>
      (id == null ? null : _exerciseById(id)) ??
      (throw const _HttpError(404, 'exercise not found'));

  LocalResponse _exercises(
    String method,
    List<String> parts,
    int? id,
    Map<String, String> query,
    Object? body,
  ) {
    if (parts.length == 1) {
      if (method == 'GET') return _listExercises(query);
      if (method == 'POST') return LocalResponse(201, _createExercise(_asMap(body)));
    } else if (parts.length == 2 && id != null) {
      if (method == 'GET') return LocalResponse(200, _exerciseOr404(id));
      if (method == 'PATCH') return LocalResponse(200, _updateExercise(id, _asMap(body)));
      if (method == 'DELETE') {
        _deleteExercise(id);
        return const LocalResponse(204);
      }
    } else if (parts.length == 3 && id != null) {
      switch ((parts[2], method)) {
        case ('tutorial', 'GET'):
          _exerciseOr404(id);
          throw const _HttpError(404, 'no tutorial available for this exercise');
        case ('records', 'GET'):
          return LocalResponse(200, _records(_exerciseOr404(id)['id'] as int));
        case ('history', 'GET'):
          final limit = int.tryParse(query['limit'] ?? '') ?? 20;
          return LocalResponse(200, _history(_exerciseOr404(id)['id'] as int, limit));
      }
    }
    throw const _HttpError(404, 'not available in local mode');
  }

  LocalResponse _listExercises(Map<String, String> query) {
    final search = (query['search'] ?? '').toLowerCase();
    final muscle = query['muscle'];
    final equipment = query['equipment'];
    final isCustom = query['is_custom'] == null ? null : query['is_custom'] == 'true';
    final matches =
        _allExercises.where((e) {
          if (search.isNotEmpty && !(e['name'] as String).toLowerCase().contains(search)) {
            return false;
          }
          if (muscle != null &&
              !(e['primary_muscles'] as List).contains(muscle) &&
              !(e['secondary_muscles'] as List).contains(muscle)) {
            return false;
          }
          if (equipment != null && e['equipment'] != equipment) return false;
          return isCustom == null || e['is_custom'] == isCustom;
        }).toList()..sort((a, b) {
          final byName = (a['name'] as String).toLowerCase().compareTo(
            (b['name'] as String).toLowerCase(),
          );
          return byName != 0 ? byName : (a['id'] as int).compareTo(b['id'] as int);
        });
    final limit = int.tryParse(query['limit'] ?? '');
    final offset = int.tryParse(query['offset'] ?? '') ?? 0;
    final page = limit == null ? matches : matches.skip(offset).take(limit).toList();
    return LocalResponse(200, page, {'x-total-count': '${matches.length}'});
  }

  String _validName(Object? raw) {
    final name = raw is String ? raw.trim() : '';
    if (name.isEmpty) throw const _HttpError(422, 'name must not be empty');
    if (name.length > 200) throw const _HttpError(422, 'name is longer than 200 characters');
    return name;
  }

  void _ensureNameFree(String name, {int? except}) {
    if (_allExercises.any((e) => e['name'] == name && e['id'] != except)) {
      throw const _HttpError(409, 'an exercise with this name already exists');
    }
  }

  /// Primary wins when a muscle is listed as both, as on the server.
  (List<String>, List<String>) _muscles(Object? primary, Object? secondary) {
    final first = <String>{...((primary as List?) ?? const []).cast<String>()}.toList();
    final second = <String>{...((secondary as List?) ?? const []).cast<String>()}
        .where((m) => !first.contains(m))
        .toList();
    return (first, second);
  }

  Map<String, dynamic> _createExercise(Map<String, dynamic> body) {
    final name = _validName(body['name']);
    _ensureNameFree(name);
    final (primary, secondary) = _muscles(body['primary_muscles'], body['secondary_muscles']);
    final exercise = {
      'id': _nextId('exercise'),
      'name': name,
      'tracks_weight': body['tracks_weight'] ?? true,
      'tracks_reps': body['tracks_reps'] ?? true,
      'tracks_distance': body['tracks_distance'] ?? false,
      'tracks_duration': body['tracks_duration'] ?? false,
      'is_custom': true,
      'equipment': body['equipment'],
      'primary_muscles': primary,
      'secondary_muscles': secondary,
    };
    _list('exercises').add(exercise);
    return exercise;
  }

  Map<String, dynamic> _updateExercise(int id, Map<String, dynamic> body) {
    final exercise = _exerciseOr404(id);
    if (exercise['is_custom'] != true) {
      throw const _HttpError(403, 'built-in exercises cannot be edited or deleted');
    }
    if (body.containsKey('name') && body['name'] != null) {
      final name = _validName(body['name']);
      _ensureNameFree(name, except: id);
      exercise['name'] = name;
    }
    for (final key in ['tracks_weight', 'tracks_reps', 'tracks_distance', 'tracks_duration']) {
      if (body[key] != null) exercise[key] = body[key];
    }
    // `equipment: null` is a real value here (clears it), not "unset".
    if (body.containsKey('equipment')) exercise['equipment'] = body['equipment'];
    if (body['primary_muscles'] != null || body['secondary_muscles'] != null) {
      final (primary, secondary) = _muscles(
        body['primary_muscles'] ?? exercise['primary_muscles'],
        body['secondary_muscles'] ?? exercise['secondary_muscles'],
      );
      exercise['primary_muscles'] = primary;
      exercise['secondary_muscles'] = secondary;
    }
    return exercise;
  }

  bool _exerciseInUse(int id) => [
    for (final r in _list('routines')) ...(r['exercises'] as List).cast<Map>(),
    for (final a in _list('activities')) ...(a['exercises'] as List).cast<Map>(),
  ].any((e) => e['exercise_id'] == id);

  void _deleteExercise(int id) {
    final exercise = _exerciseOr404(id);
    if (exercise['is_custom'] != true) {
      throw const _HttpError(403, 'built-in exercises cannot be edited or deleted');
    }
    if (_exerciseInUse(id)) {
      throw const _HttpError(409, 'this exercise is used by a routine or an activity');
    }
    _list('exercises').remove(exercise);
  }

  Map<String, dynamic> _records(int exerciseId) {
    double? weight;
    int? reps;
    for (final set in _setsOf(exerciseId)) {
      if (set['set_type'] == 'warmup') continue;
      final w = (set['weight_kg'] as num?)?.toDouble();
      final r = set['reps'] as int?;
      if (w != null && (weight == null || w > weight)) weight = w;
      if (r != null && (reps == null || r > reps)) reps = r;
    }
    return {'max_weight_kg': weight, 'max_reps': reps};
  }

  Iterable<Map<String, dynamic>> _setsOf(int exerciseId) sync* {
    for (final a in _list('activities')) {
      for (final e in (a['exercises'] as List).cast<Map<String, dynamic>>()) {
        if (e['exercise_id'] == exerciseId) yield* (e['sets'] as List).cast<Map<String, dynamic>>();
      }
    }
  }

  List<Map<String, dynamic>> _history(int exerciseId, int limit) {
    final activities = _sortedActivities(newestFirst: true)
        .where((a) => (a['exercises'] as List).any((e) => (e as Map)['exercise_id'] == exerciseId));
    return [
      for (final a in activities.take(limit))
        {
          'activity_id': a['id'],
          'activity_title': a['title'],
          'started_at': a['started_at'],
          'sets': [
            for (final e in (a['exercises'] as List).cast<Map<String, dynamic>>())
              if (e['exercise_id'] == exerciseId)
                for (final s in (e['sets'] as List).cast<Map<String, dynamic>>())
                  {
                    'set_type': s['set_type'],
                    'weight_kg': s['weight_kg'],
                    'reps': s['reps'],
                    'distance_km': s['distance_km'],
                    'duration_seconds': s['duration_seconds'],
                  },
          ],
        },
    ];
  }

  // ------------------------------------------------- routines / measurements

  Map<String, dynamic> _asMap(Object? body) {
    if (body is Map<String, dynamic>) return body;
    throw const _HttpError(422, 'the request body must be a JSON object');
  }

  LocalResponse _collection(
    String kind,
    String key,
    String method,
    List<String> parts,
    int? id,
    Object? body,
  ) {
    final rows = _list(key);
    if (parts.length == 1) {
      if (method == 'GET') {
        final sorted = [...rows];
        if (kind == 'routine') {
          sorted.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        } else {
          sorted.sort(
            (a, b) =>
                DateTime.parse(a['measured_at'] as String)
                    .compareTo(DateTime.parse(b['measured_at'] as String)),
          );
        }
        return LocalResponse(200, sorted);
      }
      if (method == 'POST') {
        final row = _build(kind, _nextId(kind), _asMap(body));
        rows.add(row);
        return LocalResponse(201, row);
      }
    } else if (parts.length == 2 && id != null) {
      final index = rows.indexWhere((r) => r['id'] == id);
      if (index < 0) throw _HttpError(404, '$kind not found');
      if (method == 'GET') return LocalResponse(200, rows[index]);
      if (method == 'PUT') return LocalResponse(200, rows[index] = _build(kind, id, _asMap(body)));
      if (method == 'DELETE') {
        final removed = rows.removeAt(index);
        if (kind == 'routine') {
          // Past activities keep their history, just no longer point at it.
          for (final a in _list('activities')) {
            if (a['routine_id'] == removed['id']) a['routine_id'] = null;
          }
        }
        return const LocalResponse(204);
      }
    }
    throw const _HttpError(404, 'not available in local mode');
  }

  Map<String, dynamic> _build(String kind, int id, Map<String, dynamic> body) {
    switch (kind) {
      case 'routine':
        return {
          'id': id,
          'name': _validName(body['name']),
          'description': body['description'],
          'exercises': _exercisesOf(body['exercises'], const [
            'target_weight_kg',
            'target_reps',
            'target_distance_km',
            'target_duration_seconds',
          ]),
        };
      case 'activity':
        final started = _timestamp(body['started_at'], 'started_at');
        final routineId = body['routine_id'] as int?;
        if (routineId != null && !_list('routines').any((r) => r['id'] == routineId)) {
          throw const _HttpError(404, 'routine not found');
        }
        return {
          'id': id,
          'title': _validName(body['title']),
          'description': body['description'],
          'started_at': started,
          'ended_at': body['ended_at'] == null ? null : _timestamp(body['ended_at'], 'ended_at'),
          'routine_id': routineId,
          'exercises': _exercisesOf(body['exercises'], const [
            'weight_kg',
            'reps',
            'distance_km',
            'duration_seconds',
          ]),
        };
      default:
        final row = {..._measurementFields(body), 'id': id};
        row['measured_at'] = _timestamp(body['measured_at'], 'measured_at');
        return row;
    }
  }

  Map<String, dynamic> _measurementFields(Map<String, dynamic> body) => {
    for (final field in _measurementKeys) field: body[field],
  };

  String _timestamp(Object? raw, String field) {
    final parsed = raw is String ? DateTime.tryParse(raw) : null;
    if (parsed == null) throw _HttpError(422, '$field must be an ISO 8601 timestamp');
    return parsed.toUtc().toIso8601String();
  }

  /// Routine/activity exercises as stored: ids and positions assigned, every
  /// exercise checked to exist, sets reduced to the known columns.
  List<Map<String, dynamic>> _exercisesOf(Object? raw, List<String> setFields) {
    final items = ((raw as List?) ?? const []).cast<Map<String, dynamic>>();
    return [
      for (var i = 0; i < items.length; i++)
        {
          'id': _nextId('row'),
          'position': i,
          'exercise_id': _exerciseOr422(items[i]['exercise_id']),
          'superset_group': items[i]['superset_group'],
          'notes': items[i]['notes'],
          'sets': [
            for (var j = 0; j < ((items[i]['sets'] as List?) ?? const []).length; j++)
              {
                'id': _nextId('row'),
                'position': j,
                'set_type': (items[i]['sets'] as List)[j]['set_type'] ?? 'normal',
                for (final f in setFields) f: (items[i]['sets'] as List)[j][f],
              },
          ],
        },
    ];
  }

  int _exerciseOr422(Object? id) {
    if (id is int && _exerciseById(id) != null) return id;
    throw _HttpError(422, 'exercise $id does not exist');
  }

  // ------------------------------------------------------------- activities

  List<Map<String, dynamic>> _sortedActivities({required bool newestFirst}) {
    final sorted = [..._list('activities')]
      ..sort((a, b) {
        final byTime = DateTime.parse(a['started_at'] as String)
            .compareTo(DateTime.parse(b['started_at'] as String));
        return byTime != 0 ? byTime : (a['id'] as int).compareTo(b['id'] as int);
      });
    return newestFirst ? sorted.reversed.toList() : sorted;
  }

  LocalResponse _activities(
    String method,
    List<String> parts,
    int? id,
    Map<String, String> query,
    Object? body,
  ) {
    if (parts.length == 1 && method == 'GET') {
      final since = DateTime.tryParse(query['since'] ?? '');
      final until = DateTime.tryParse(query['until'] ?? '');
      return LocalResponse(200, [
        for (final a in _sortedActivities(newestFirst: true))
          if ((since == null || !DateTime.parse(a['started_at'] as String).isBefore(since)) &&
              (until == null || !DateTime.parse(a['started_at'] as String).isAfter(until)))
            a,
      ]);
    }
    return _collection('activity', 'activities', method, parts, id, body);
  }

  // ---------------------------------------------------------------- profile

  LocalResponse _profile(
    String method,
    List<String> parts,
    Map<String, String> query,
    Object? body,
  ) {
    final sub = parts.length > 1 ? parts[1] : '';
    switch ((sub, method)) {
      case ('', 'GET'):
        return LocalResponse(200, _profileJson());
      case ('', 'PATCH'):
        final data = _asMap(body);
        final profile = _doc!['profile'] as Map<String, dynamic>;
        if (data.containsKey('height_cm')) profile['height_cm'] = data['height_cm'];
        if (data['unit_system'] != null) profile['unit_system'] = data['unit_system'];
        return LocalResponse(200, _profileJson());
      case ('export', 'GET'):
        final stamp = _clock().toUtc().toIso8601String().substring(0, 10);
        return LocalResponse(200, _export(), {
          'content-disposition': 'attachment; filename="dinatos-export-$stamp.json"',
        });
      case ('import', 'POST'):
        return LocalResponse(200, _import(_asMap(body), query['mode'] ?? 'merge'));
      case ('data', 'DELETE'):
        return LocalResponse(200, {'deleted': _clear()});
    }
    throw const _HttpError(404, 'not available in local mode');
  }

  Map<String, dynamic> _profileJson() => {
    ...(_doc!['profile'] as Map<String, dynamic>),
    'has_workoutx_api_key': false,
  };

  Map<String, dynamic> _count({
    int exercises = 0,
    int routines = 0,
    int activities = 0,
    int measurements = 0,
  }) => {
    'exercises': exercises,
    'routines': routines,
    'activities': activities,
    'measurements': measurements,
  };

  Map<String, dynamic> _clear() {
    final counts = _count(
      routines: _list('routines').length,
      activities: _list('activities').length,
      measurements: _list('measurements').length,
    );
    _doc!['routines'] = <dynamic>[];
    _doc!['activities'] = <dynamic>[];
    _doc!['measurements'] = <dynamic>[];
    final unused = _list('exercises').where((e) => !_exerciseInUse(e['id'] as int)).toList();
    _list('exercises').removeWhere(unused.contains);
    counts['exercises'] = unused.length;
    return counts;
  }

  // ---------------------------------------------------------- export/import

  /// The same document as the server's `GET /profile/export` (see
  /// `backend/src/dinatos_backend/services/user_export.py`): no ids, exercises
  /// by name, routines referenced by position -- which is what makes a file
  /// from here importable there, and the other way round.
  Map<String, dynamic> _export() {
    final routines = [..._list('routines')]
      ..sort((a, b) {
        final byName = (a['name'] as String).compareTo(b['name'] as String);
        return byName != 0 ? byName : (a['id'] as int).compareTo(b['id'] as int);
      });
    final activities = _sortedActivities(newestFirst: false);
    final measurements = [..._list('measurements')]
      ..sort(
        (a, b) =>
            DateTime.parse(a['measured_at'] as String)
                .compareTo(DateTime.parse(b['measured_at'] as String)),
      );
    final refs = {for (var i = 0; i < routines.length; i++) routines[i]['id'] as int: i + 1};
    final usedIds = {
      for (final r in routines)
        for (final e in (r['exercises'] as List).cast<Map>()) e['exercise_id'] as int,
      for (final a in activities)
        for (final e in (a['exercises'] as List).cast<Map>()) e['exercise_id'] as int,
    };
    final used = _allExercises.where((e) => usedIds.contains(e['id'])).toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    final names = {for (final e in used) e['id'] as int: e['name'] as String};

    List<Map<String, dynamic>> exercisesOut(List items, List<String> setFields) => [
      for (final item in items.cast<Map<String, dynamic>>())
        {
          'exercise': names[item['exercise_id']],
          'superset_group': item['superset_group'],
          'notes': item['notes'],
          'sets': [
            for (final s in (item['sets'] as List).cast<Map<String, dynamic>>())
              {'set_type': s['set_type'], for (final f in setFields) f: s[f]},
          ],
        },
    ];

    final profile = _doc!['profile'] as Map<String, dynamic>;
    return {
      'format': _exportFormat,
      'format_version': 1,
      'exported_at': _clock().toUtc().toIso8601String(),
      'app_version': appVersion,
      'profile': {'height_cm': profile['height_cm'], 'unit_system': profile['unit_system']},
      'exercises': [
        for (final e in used)
          {
            'name': e['name'],
            'tracks_weight': e['tracks_weight'],
            'tracks_reps': e['tracks_reps'],
            'tracks_distance': e['tracks_distance'],
            'tracks_duration': e['tracks_duration'],
            'equipment': e['equipment'],
            'primary_muscles': e['primary_muscles'],
            'secondary_muscles': e['secondary_muscles'],
          },
      ],
      'routines': [
        for (final r in routines)
          {
            'ref': refs[r['id']],
            'name': r['name'],
            'description': r['description'],
            'exercises': exercisesOut(r['exercises'] as List, const [
              'target_weight_kg',
              'target_reps',
              'target_distance_km',
              'target_duration_seconds',
            ]),
          },
      ],
      'activities': [
        for (final a in activities)
          {
            'title': a['title'],
            'description': a['description'],
            'started_at': a['started_at'],
            'ended_at': a['ended_at'],
            'routine_ref': a['routine_id'] == null ? null : refs[a['routine_id']],
            'exercises': exercisesOut(a['exercises'] as List, const [
              'weight_kg',
              'reps',
              'distance_km',
              'duration_seconds',
            ]),
          },
      ],
      'measurements': [
        for (final m in measurements) {for (final f in _measurementKeys) f: m[f]},
      ],
    };
  }

  Map<String, dynamic> _import(Map<String, dynamic> document, String mode) {
    if (mode != 'merge' && mode != 'replace') {
      throw const _HttpError(422, 'mode must be merge or replace');
    }
    if (document['format'] != _exportFormat || document['format_version'] != 1) {
      throw const _HttpError(422, 'That file is not a Dinatos export.');
    }
    final defined = <String, Map<String, dynamic>>{};
    for (final e in ((document['exercises'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final name = _validName(e['name']);
      if (defined.containsKey(name)) {
        throw const _HttpError(422, "'exercises' lists the same name more than once");
      }
      defined[name] = e;
    }
    final routinesIn = ((document['routines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final activitiesIn = ((document['activities'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final measurementsIn = ((document['measurements'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final known = {for (final e in _allExercises) e['name'] as String};
    final refs = {for (final r in routinesIn) r['ref']};
    if (refs.length != routinesIn.length) throw const _HttpError(422, "'routines' reuses a ref");
    for (final item in [
      for (final r in routinesIn) ...((r['exercises'] as List?) ?? const []).cast<Map>(),
      for (final a in activitiesIn) ...((a['exercises'] as List?) ?? const []).cast<Map>(),
    ]) {
      final name = item['exercise'];
      if (!defined.containsKey(name) && !known.contains(name)) {
        throw _HttpError(
          422,
          "exercise '$name' is used but neither defined in 'exercises' nor present",
        );
      }
    }
    for (final a in activitiesIn) {
      if (a['routine_ref'] != null && !refs.contains(a['routine_ref'])) {
        throw _HttpError(422, "activity '${a['title']}': unknown routine_ref");
      }
    }
    // Everything is checked before anything is written, as on the server.
    final dates = [
      for (final a in activitiesIn) _timestamp(a['started_at'], 'started_at'),
      for (final m in measurementsIn) _timestamp(m['measured_at'], 'measured_at'),
    ];
    final created = _count();
    final skipped = _count();
    var deleted = _count();
    if (mode == 'replace') {
      deleted = _count(
        routines: _list('routines').length,
        activities: _list('activities').length,
        measurements: _list('measurements').length,
      );
      _doc!['routines'] = <dynamic>[];
      _doc!['activities'] = <dynamic>[];
      _doc!['measurements'] = <dynamic>[];
    }

    final knownRoutines = <String, int>{};
    for (final r in _list('routines').reversed) {
      knownRoutines[r['name'] as String] = r['id'] as int; // lowest id wins
    }
    final knownActivities = {
      for (final a in _list('activities')) '${a['title']}|${a['started_at']}',
    };
    final knownMeasurements = {for (final m in _list('measurements')) m['measured_at']};

    final profile = document['profile'];
    if (profile is Map) {
      final own = _doc!['profile'] as Map<String, dynamic>;
      own['height_cm'] = profile['height_cm'];
      if (profile['unit_system'] != null) own['unit_system'] = profile['unit_system'];
    }

    final ids = <String, int>{for (final e in _allExercises) e['name'] as String: e['id'] as int};
    for (final entry in defined.entries) {
      if (ids.containsKey(entry.key)) continue;
      final e = entry.value;
      final (primary, secondary) = _muscles(e['primary_muscles'], e['secondary_muscles']);
      final id = _nextId('exercise');
      _list('exercises').add({
        'id': id,
        'name': entry.key,
        'tracks_weight': e['tracks_weight'] ?? true,
        'tracks_reps': e['tracks_reps'] ?? true,
        'tracks_distance': e['tracks_distance'] ?? false,
        'tracks_duration': e['tracks_duration'] ?? false,
        'is_custom': true,
        'equipment': e['equipment'],
        'primary_muscles': primary,
        'secondary_muscles': secondary,
      });
      ids[entry.key] = id;
      created['exercises'] = (created['exercises'] as int) + 1;
    }

    List<Map<String, dynamic>> bodies(Object? raw) => [
      for (final item in ((raw as List?) ?? const []).cast<Map<String, dynamic>>())
        {
          'exercise_id': ids[item['exercise']],
          'superset_group': item['superset_group'],
          'notes': item['notes'],
          'sets': ((item['sets'] as List?) ?? const []),
        },
    ];

    final routineIds = <Object?, int>{};
    for (final r in routinesIn) {
      final existing = knownRoutines[r['name']];
      if (existing != null) {
        routineIds[r['ref']] = existing;
        skipped['routines'] = (skipped['routines'] as int) + 1;
        continue;
      }
      final row = _build('routine', _nextId('routine'), {
        ...r,
        'exercises': bodies(r['exercises']),
      });
      _list('routines').add(row);
      routineIds[r['ref']] = row['id'] as int;
      created['routines'] = (created['routines'] as int) + 1;
    }
    for (var i = 0; i < activitiesIn.length; i++) {
      final a = activitiesIn[i];
      if (!knownActivities.add('${a['title']}|${dates[i]}')) {
        skipped['activities'] = (skipped['activities'] as int) + 1;
        continue;
      }
      _list('activities').add(
        _build('activity', _nextId('activity'), {
          ...a,
          'routine_id': a['routine_ref'] == null ? null : routineIds[a['routine_ref']],
          'exercises': bodies(a['exercises']),
        }),
      );
      created['activities'] = (created['activities'] as int) + 1;
    }
    for (var i = 0; i < measurementsIn.length; i++) {
      final stamp = dates[activitiesIn.length + i];
      if (!knownMeasurements.add(stamp)) {
        skipped['measurements'] = (skipped['measurements'] as int) + 1;
        continue;
      }
      _list('measurements').add(_build('measurement', _nextId('measurement'), measurementsIn[i]));
      created['measurements'] = (created['measurements'] as int) + 1;
    }
    return {'mode': mode, 'created': created, 'skipped': skipped, 'deleted': deleted};
  }

  // ------------------------------------------------------------ first launch

  /// Same starter routines a new server account gets (see
  /// `backend/src/dinatos_backend/services/starter_routines.py`).
  void _seedStarterRoutines() {
    final byName = {for (final e in _builtIn) e['name'] as String: e['id'] as int};
    for (final (name, description, moves) in _starterTemplates) {
      final present = [
        for (final m in moves)
          if (byName.containsKey(m.$1)) m,
      ];
      if (present.isEmpty) continue;
      _list('routines').add(
        _build('routine', _nextId('routine'), {
          'name': name,
          'description': description,
          'exercises': [
            for (final (exercise, sets, reps, seconds) in present)
              {
                'exercise_id': byName[exercise],
                'sets': [
                  for (var i = 0; i < sets; i++)
                    {'target_reps': reps, 'target_duration_seconds': seconds},
                ],
              },
          ],
        }),
      );
    }
  }
}

typedef _Move = (String, int, int?, int?);

const List<(String, String, List<_Move>)> _starterTemplates = [
  (
    'Push',
    'Chest, shoulders and triceps.',
    [
      ('Barbell Bench Press - Medium Grip', 4, 8, null),
      ('Standing Military Press', 3, 8, null),
      ('Barbell Incline Bench Press - Medium Grip', 3, 10, null),
      ('Side Lateral Raise', 3, 15, null),
      ('Triceps Pushdown', 3, 12, null),
    ],
  ),
  (
    'Pull',
    'Back and biceps.',
    [
      ('Barbell Deadlift', 3, 5, null),
      ('Pullups', 3, 8, null),
      ('Bent Over Barbell Row', 4, 8, null),
      ('Face Pull', 3, 15, null),
      ('Barbell Curl', 3, 10, null),
    ],
  ),
  (
    'Legs',
    'Quads, hamstrings, glutes and calves.',
    [
      ('Barbell Squat', 4, 6, null),
      ('Romanian Deadlift', 3, 8, null),
      ('Leg Press', 3, 12, null),
      ('Lying Leg Curls', 3, 12, null),
      ('Standing Calf Raises', 4, 15, null),
    ],
  ),
  (
    'Upper body',
    'Chest, back, shoulders and arms in one session.',
    [
      ('Barbell Bench Press - Medium Grip', 4, 8, null),
      ('Bent Over Barbell Row', 4, 8, null),
      ('Dumbbell Shoulder Press', 3, 10, null),
      ('Wide-Grip Lat Pulldown', 3, 10, null),
      ('Dumbbell Bicep Curl', 3, 12, null),
      ('Triceps Pushdown', 3, 12, null),
    ],
  ),
  (
    'Lower body',
    'Legs, glutes and core.',
    [
      ('Barbell Squat', 4, 8, null),
      ('Barbell Hip Thrust', 3, 10, null),
      ('Seated Leg Curl', 3, 12, null),
      ('Leg Extensions', 3, 12, null),
      ('Hanging Leg Raise', 3, 12, null),
    ],
  ),
  (
    'Full body',
    'A balanced session for three days a week.',
    [
      ('Barbell Squat', 3, 5, null),
      ('Barbell Bench Press - Medium Grip', 3, 5, null),
      ('Bent Over Barbell Row', 3, 8, null),
      ('Standing Military Press', 3, 8, null),
      ('Romanian Deadlift', 2, 8, null),
      ('Plank', 3, null, 45),
    ],
  ),
];

const _measurementKeys = [
  'measured_at',
  'weight_kg',
  'fat_percent',
  'muscle_mass_kg',
  'bone_mass_kg',
  'bmi',
  'dci_kcal',
  'metabolic_age',
  'water_percent',
  'visceral_fat',
  'right_arm_fat_percent',
  'right_arm_muscle_kg',
  'left_arm_fat_percent',
  'left_arm_muscle_kg',
  'right_leg_fat_percent',
  'right_leg_muscle_kg',
  'left_leg_fat_percent',
  'left_leg_muscle_kg',
  'trunk_fat_percent',
  'trunk_muscle_kg',
  'neck_cm',
  'shoulder_cm',
  'chest_cm',
  'left_bicep_cm',
  'right_bicep_cm',
  'left_forearm_cm',
  'right_forearm_cm',
  'abdomen_cm',
  'waist_cm',
  'hips_cm',
  'left_thigh_cm',
  'right_thigh_cm',
  'left_calf_cm',
  'right_calf_cm',
];
