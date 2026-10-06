import 'dart:convert';
import 'dart:io';

import 'package:dinatos_frontend/core/local/local_api.dart';
import 'package:dinatos_frontend/core/local/local_document_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<Map<String, dynamic>>> _catalog() async =>
    (jsonDecode(File('assets/exercise_catalog.json').readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>();

LocalApi _api([LocalDocumentStorage? storage, DateTime? now]) => LocalApi(
  storage: storage ?? MemoryLocalDocumentStorage(),
  loadCatalog: _catalog,
  appVersion: 'test',
  clock: () => now ?? DateTime.utc(2026, 10, 6, 12),
);

Future<LocalResponse> _call(
  LocalApi api,
  String method,
  String path, {
  Map<String, String>? query,
  Object? body,
}) => api.handle(
  method,
  Uri(path: path, queryParameters: query),
  body == null ? null : jsonDecode(jsonEncode(body)),
);

Future<Map<String, dynamic>> _ok(Future<LocalResponse> future, [int status = 200]) async {
  final response = await future;
  expect(response.status, status, reason: '${response.body}');
  return response.body as Map<String, dynamic>;
}

Future<List<dynamic>> _okList(Future<LocalResponse> future) async {
  final response = await future;
  expect(response.status, 200, reason: '${response.body}');
  return response.body as List<dynamic>;
}

Future<int> _exerciseId(LocalApi api, String name) async {
  final found = await _okList(_call(api, 'GET', '/exercises', query: {'search': name}));
  return (found.firstWhere((e) => e['name'] == name) as Map)['id'] as int;
}

Map<String, dynamic> _activity(
  int exerciseId, {
  String title = 'Chest day',
  String at = '2026-10-01T10:00:00Z',
}) => {
  'title': title,
  'started_at': at,
  'ended_at': '2026-10-01T11:00:00Z',
  'exercises': [
    {
      'exercise_id': exerciseId,
      'sets': [
        {'set_type': 'warmup', 'weight_kg': 100.0, 'reps': 20},
        {'set_type': 'normal', 'weight_kg': 60.0, 'reps': 8},
        {'set_type': 'normal', 'weight_kg': 62.5, 'reps': 6},
      ],
    },
  ],
};

void main() {
  group('first launch', () {
    test('ships the built-in catalog and the starter routines', () async {
      final api = _api();
      final page = await _call(api, 'GET', '/exercises', query: {'limit': '5', 'offset': '0'});
      expect(page.body as List, hasLength(5));
      expect(int.parse(page.headers['x-total-count']!), greaterThan(500));

      final routines = await _okList(_call(api, 'GET', '/routines'));
      expect(routines.map((r) => (r as Map)['name']), contains('Push'));
      final push = routines.firstWhere((r) => (r as Map)['name'] == 'Push') as Map;
      expect((push['exercises'] as List).length, 5);
      expect(((push['exercises'] as List).first as Map)['sets'], hasLength(4));
    });

    test('acts as one signed-in person with no account system', () async {
      final api = _api();
      final me = await _ok(_call(api, 'GET', '/auth/me'));
      expect(me['is_admin'], false);
      expect((await _call(api, 'POST', '/auth/logout')).status, 204);
      expect((await _call(api, 'GET', '/admin/users')).status, 404);
    });

    test('keeps its data across restarts, and seeds the starters only once', () async {
      final storage = MemoryLocalDocumentStorage();
      final first = _api(storage);
      final id = await _exerciseId(first, 'Barbell Squat');
      await _ok(_call(first, 'POST', '/activities', body: _activity(id)), 201);
      for (final routine in await _okList(_call(first, 'GET', '/routines'))) {
        await _call(first, 'DELETE', '/routines/${(routine as Map)['id']}');
      }

      final second = _api(storage);
      expect(await _okList(_call(second, 'GET', '/activities')), hasLength(1));
      expect(await _okList(_call(second, 'GET', '/routines')), isEmpty);
    });
  });

  group('exercises', () {
    test('search is case-insensitive, and filters combine', () async {
      final api = _api();
      final squats = await _okList(_call(api, 'GET', '/exercises', query: {'search': 'SQUAT'}));
      expect(squats, isNotEmpty);
      expect(
        squats.every((e) => (e as Map)['name'].toString().toLowerCase().contains('squat')),
        isTrue,
      );

      final barbellQuads = await _okList(
        _call(api, 'GET', '/exercises', query: {'muscle': 'quadriceps', 'equipment': 'barbell'}),
      );
      expect(barbellQuads, isNotEmpty);
      expect(barbellQuads.every((e) => (e as Map)['equipment'] == 'barbell'), isTrue);
      expect(await _okList(_call(api, 'GET', '/exercises', query: {'is_custom': 'true'})), isEmpty);
    });

    test('a custom exercise can be created, edited and deleted; built-ins cannot', () async {
      final api = _api();
      final created = await _ok(
        _call(
          api,
          'POST',
          '/exercises',
          body: {
            'name': 'Prowler Carry Test',
            'tracks_reps': false,
            'tracks_duration': true,
            'equipment': 'other',
            'primary_muscles': ['quadriceps', 'quadriceps'],
            'secondary_muscles': ['quadriceps', 'calves'],
          },
        ),
        201,
      );
      expect(created['is_custom'], true);
      expect(created['tracks_duration'], true);
      expect(created['primary_muscles'], ['quadriceps']);
      expect(created['secondary_muscles'], ['calves']);

      final id = created['id'] as int;
      final edited = await _ok(
        _call(api, 'PATCH', '/exercises/$id', body: {'tracks_reps': true, 'equipment': null}),
      );
      expect(edited['tracks_reps'], true);
      expect(edited['equipment'], isNull);
      expect(edited['tracks_duration'], true);

      expect(
        (await _call(api, 'POST', '/exercises', body: {'name': 'Prowler Carry Test'})).status,
        409,
      );
      expect((await _call(api, 'POST', '/exercises', body: {'name': 'Barbell Squat'})).status, 409);
      expect((await _call(api, 'POST', '/exercises', body: {'name': '  '})).status, 422);

      final builtIn = await _exerciseId(api, 'Barbell Squat');
      expect((await _call(api, 'PATCH', '/exercises/$builtIn', body: {'name': 'x'})).status, 403);
      expect((await _call(api, 'DELETE', '/exercises/$builtIn')).status, 403);

      await _ok(_call(api, 'POST', '/activities', body: _activity(id)), 201);
      expect((await _call(api, 'DELETE', '/exercises/$id')).status, 409);
      for (final a in await _okList(_call(api, 'GET', '/activities'))) {
        await _call(api, 'DELETE', '/activities/${(a as Map)['id']}');
      }
      expect((await _call(api, 'DELETE', '/exercises/$id')).status, 204);
      expect((await _call(api, 'GET', '/exercises/$id')).status, 404);
    });

    test('has no tutorials, and says so the way the server does', () async {
      final api = _api();
      final id = await _exerciseId(api, 'Barbell Squat');
      final response = await _call(api, 'GET', '/exercises/$id/tutorial');
      expect(response.status, 404);
      expect((response.body as Map)['detail'], contains('no tutorial'));
    });
  });

  group('activities', () {
    test('are listed newest first and can be filtered by time', () async {
      final api = _api();
      final id = await _exerciseId(api, 'Barbell Squat');
      for (final (title, at) in [
        ('A', '2026-09-01T10:00:00Z'),
        ('B', '2026-10-01T10:00:00Z'),
        ('C', '2026-09-15T10:00:00Z'),
      ]) {
        await _ok(
          _call(
            api,
            'POST',
            '/activities',
            body: _activity(id, title: title, at: at),
          ),
          201,
        );
      }
      final all = await _okList(_call(api, 'GET', '/activities'));
      expect(all.map((a) => (a as Map)['title']), ['B', 'C', 'A']);
      final since = await _okList(
        _call(api, 'GET', '/activities', query: {'since': '2026-09-10T00:00:00Z'}),
      );
      expect(since.map((a) => (a as Map)['title']), ['B', 'C']);
      final until = await _okList(
        _call(api, 'GET', '/activities', query: {'until': '2026-09-10T00:00:00Z'}),
      );
      expect(until.map((a) => (a as Map)['title']), ['A']);
    });

    test('give sets and exercises ids and positions, and replace wholesale', () async {
      final api = _api();
      final id = await _exerciseId(api, 'Barbell Squat');
      final created = await _ok(_call(api, 'POST', '/activities', body: _activity(id)), 201);
      final exercise = (created['exercises'] as List).single as Map;
      expect(exercise['position'], 0);
      expect((exercise['sets'] as List).map((s) => (s as Map)['position']), [0, 1, 2]);
      expect(((exercise['sets'] as List).first as Map)['id'], isA<int>());

      final replaced = await _ok(
        _call(
          api,
          'PUT',
          '/activities/${created['id']}',
          body: {..._activity(id), 'title': 'Renamed', 'exercises': []},
        ),
      );
      expect(replaced['title'], 'Renamed');
      expect(replaced['exercises'], isEmpty);
    });

    test('refuse an unknown exercise or routine and a missing title', () async {
      final api = _api();
      expect((await _call(api, 'POST', '/activities', body: _activity(999999))).status, 422);
      final id = await _exerciseId(api, 'Barbell Squat');
      expect(
        (await _call(
          api,
          'POST',
          '/activities',
          body: {..._activity(id), 'routine_id': 4242},
        )).status,
        404,
      );
      expect(
        (await _call(api, 'POST', '/activities', body: {..._activity(id), 'title': ''})).status,
        422,
      );
      expect((await _call(api, 'GET', '/activities/77')).status, 404);
    });

    test('history and records ignore warm-ups, newest session first', () async {
      final api = _api();
      final id = await _exerciseId(api, 'Barbell Squat');
      await _ok(
        _call(
          api,
          'POST',
          '/activities',
          body: _activity(id, title: 'Old', at: '2026-09-01T10:00:00Z'),
        ),
        201,
      );
      await _ok(
        _call(
          api,
          'POST',
          '/activities',
          body: _activity(id, title: 'New', at: '2026-10-01T10:00:00Z'),
        ),
        201,
      );

      final records = await _ok(_call(api, 'GET', '/exercises/$id/records'));
      expect(records['max_weight_kg'], 62.5); // not the 100 kg warm-up
      expect(records['max_reps'], 8); // not the 20-rep warm-up

      final history = await _okList(
        _call(api, 'GET', '/exercises/$id/history', query: {'limit': '1'}),
      );
      expect(history, hasLength(1));
      expect((history.single as Map)['activity_title'], 'New');
      expect(((history.single as Map)['sets'] as List), hasLength(3));

      final other = await _exerciseId(api, 'Pullups');
      final empty = await _ok(_call(api, 'GET', '/exercises/$other/records'));
      expect(empty['max_weight_kg'], isNull);
      expect(empty['max_reps'], isNull);
    });
  });

  group('measurements and profile', () {
    test('measurements are stored and listed oldest first', () async {
      final api = _api();
      await _ok(
        _call(
          api,
          'POST',
          '/measurements',
          body: {'measured_at': '2026-10-02T08:00:00Z', 'weight_kg': 80.5},
        ),
        201,
      );
      final first = await _ok(
        _call(
          api,
          'POST',
          '/measurements',
          body: {'measured_at': '2026-09-02T08:00:00Z', 'weight_kg': 82},
        ),
        201,
      );
      final list = await _okList(_call(api, 'GET', '/measurements'));
      expect(list.map((m) => (m as Map)['weight_kg']), [82, 80.5]);
      await _ok(
        _call(
          api,
          'PUT',
          '/measurements/${first['id']}',
          body: {'measured_at': '2026-09-02T08:00:00Z', 'waist_cm': 90},
        ),
      );
      expect(((await _ok(_call(api, 'GET', '/measurements/${first['id']}')))['waist_cm']), 90);
      expect((await _call(api, 'DELETE', '/measurements/${first['id']}')).status, 204);
      expect((await _call(api, 'GET', '/measurements/${first['id']}')).status, 404);
    });

    test('the profile starts metric and can be updated', () async {
      final api = _api();
      expect((await _ok(_call(api, 'GET', '/profile')))['unit_system'], 'metric');
      final updated = await _ok(
        _call(api, 'PATCH', '/profile', body: {'height_cm': 181.5, 'unit_system': 'imperial'}),
      );
      expect(updated['height_cm'], 181.5);
      expect(updated['unit_system'], 'imperial');
      expect(updated['has_workoutx_api_key'], false);
    });
  });
}
