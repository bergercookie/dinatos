import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/activity.dart';
import '../../../models/set_type.dart';
import '../../../models/uid.dart';
import 'live_session.dart';

/// A live workout as written to disk, plus whose it is -- so a different
/// account logging in on the same device doesn't inherit it.
class PersistedLiveSession {
  const PersistedLiveSession({required this.session, this.ownerId});

  final LiveActivitySession session;
  final int? ownerId;

  Map<String, dynamic> toJson() => {
    'owner_id': ownerId,
    'started_at': session.startedAt.toUtc().toIso8601String(),
    'ended_at': session.endedAt?.toUtc().toIso8601String(),
    'clock_origin': session.clockOrigin.toUtc().toIso8601String(),
    'paused_at': session.pausedAt?.toUtc().toIso8601String(),
    'saved_activity_id': session.savedActivityId,
    'saved_title': session.savedTitle,
    'pending_title': session.pendingTitle,
    'routine_id': session.routineId,
    'routine_name': session.routineName,
    // `ActivityExercise.toJson` is exactly the shape wanted here (no server ids).
    'exercises': session.exercises.map((e) => e.toJson()).toList(),
  };

  static PersistedLiveSession fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) {
      final raw = json[key] as String?;
      return raw == null ? null : DateTime.parse(raw).toLocal();
    }

    return PersistedLiveSession(
      ownerId: json['owner_id'] as int?,
      session: LiveActivitySession(
        startedAt: time('started_at')!,
        endedAt: time('ended_at'),
        clockOrigin: time('clock_origin'),
        pausedAt: time('paused_at'),
        savedActivityId: json['saved_activity_id'] as int?,
        savedTitle: json['saved_title'] as String?,
        pendingTitle: json['pending_title'] as String?,
        routineId: json['routine_id'] as int?,
        routineName: json['routine_name'] as String?,
        exercises: (json['exercises'] as List<dynamic>)
            .map((e) => _exerciseFromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    );
  }
}

ActivityExercise _exerciseFromJson(Map<String, dynamic> json) => ActivityExercise(
  uid: nextUid(),
  exerciseId: json['exercise_id'] as int,
  supersetGroup: json['superset_group'] as int?,
  notes: json['notes'] as String?,
  sets: (json['sets'] as List<dynamic>).map((raw) {
    final set = raw as Map<String, dynamic>;
    return ActivitySet(
      uid: nextUid(),
      setType: SetType.fromJson(set['set_type'] as String),
      weightKg: (set['weight_kg'] as num?)?.toDouble(),
      reps: set['reps'] as int?,
      distanceKm: (set['distance_km'] as num?)?.toDouble(),
      durationSeconds: set['duration_seconds'] as int?,
    );
  }).toList(),
);

/// Where the in-progress workout survives the app being killed. Persisting is
/// best effort: a failure must never get in the way of logging a set.
abstract class LiveSessionStorage {
  Future<PersistedLiveSession?> read();

  /// Writes [session], or clears the stored one when it is null.
  Future<void> write(PersistedLiveSession? session);
}

class NoopLiveSessionStorage implements LiveSessionStorage {
  const NoopLiveSessionStorage();

  @override
  Future<PersistedLiveSession?> read() async => null;

  @override
  Future<void> write(PersistedLiveSession? session) async {}
}

class PrefsLiveSessionStorage implements LiveSessionStorage {
  const PrefsLiveSessionStorage();

  static const _key = 'live_workout_session';

  @override
  Future<PersistedLiveSession?> read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return null;
      return PersistedLiveSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      // Unreadable (corrupt, or written by an incompatible version): start clean.
      debugPrint('Could not restore the live workout: $error');
      return null;
    }
  }

  @override
  Future<void> write(PersistedLiveSession? session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (session == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode(session.toJson()));
      }
    } catch (error) {
      debugPrint('Could not persist the live workout: $error');
    }
  }
}
