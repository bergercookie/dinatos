import 'package:dinatos_frontend/core/auth/auth_notifier.dart';
import 'package:dinatos_frontend/core/auth/auth_state.dart';
import 'package:dinatos_frontend/core/auth/token_storage.dart';
import 'package:dinatos_frontend/features/activities/live/live_session.dart';
import 'package:dinatos_frontend/features/activities/live/live_session_storage.dart';
import 'package:dinatos_frontend/models/activity.dart';
import 'package:dinatos_frontend/models/set_type.dart';
import 'package:dinatos_frontend/models/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fakes.dart';

class _MemoryStorage implements LiveSessionStorage {
  PersistedLiveSession? stored;
  var writes = 0;

  @override
  Future<PersistedLiveSession?> read() async => stored;

  @override
  Future<void> write(PersistedLiveSession? session) async {
    writes++;
    stored = session;
  }
}

class _NoToken implements TokenStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
}

class _TestAuth extends AuthNotifier {
  _TestAuth() : super(buildMockDio(), _NoToken());

  void signInAs(AuthState next) => state = next;
}

void main() {
  final session = LiveActivitySession(
    startedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    clockOrigin: DateTime.utc(2026, 1, 2, 3, 14, 5),
    pausedAt: DateTime.utc(2026, 1, 2, 3, 30),
    exercises: const [
      ActivityExercise(
        exerciseId: 7,
        notes: 'felt heavy',
        sets: [ActivitySet(setType: SetType.warmup, weightKg: 42.5, reps: 8, rpe: 7.5)],
      ),
    ],
  );

  test('a session survives a JSON round trip, clock and sets included', () {
    final restored = PersistedLiveSession.fromJson(
      PersistedLiveSession(session: session, ownerId: 3).toJson(),
    ).session;

    expect(restored.startedAt.isAtSameMomentAs(session.startedAt), isTrue);
    expect(restored.clockOrigin.isAtSameMomentAs(session.clockOrigin), isTrue);
    expect(restored.pausedAt!.isAtSameMomentAs(session.pausedAt!), isTrue);
    expect(restored.endedAt, isNull);
    final exercise = restored.exercises.single;
    expect(exercise.exerciseId, 7);
    expect(exercise.notes, 'felt heavy');
    expect(exercise.sets.single.setType, SetType.warmup);
    expect(exercise.sets.single.weightKg, 42.5);
    expect(exercise.sets.single.reps, 8);
    expect(exercise.sets.single.rpe, 7.5);
  });

  test('isSaved/savedActivityId/savedTitle survive a round trip too', () {
    final saved = session.copyWith(savedActivityId: 42, savedTitle: 'Leg day');

    final restored = PersistedLiveSession.fromJson(
      PersistedLiveSession(session: saved, ownerId: 3).toJson(),
    ).session;

    expect(restored.isSaved, isTrue);
    expect(restored.savedActivityId, 42);
    expect(restored.savedTitle, 'Leg day');
  });

  test('PrefsLiveSessionStorage writes, reads back and clears', () async {
    SharedPreferences.setMockInitialValues({});
    const storage = PrefsLiveSessionStorage();
    expect(await storage.read(), isNull);

    await storage.write(PersistedLiveSession(session: session, ownerId: 3));
    final read = await storage.read();
    expect(read!.ownerId, 3);
    expect(read.session.exercises, hasLength(1));

    await storage.write(null);
    expect(await storage.read(), isNull);
  });

  test('PrefsLiveSessionStorage treats corrupt data as no session', () async {
    SharedPreferences.setMockInitialValues({'live_workout_session': '{not json'});
    expect(await const PrefsLiveSessionStorage().read(), isNull);
  });

  test('every change is persisted, and discard() clears it', () {
    final storage = _MemoryStorage();
    final notifier = LiveActivityNotifier(storage: storage, currentUserId: () => 9)..start();
    expect(storage.stored!.ownerId, 9);

    notifier.addExercise(1);
    expect(storage.stored!.session.exercises, hasLength(1));

    notifier.discard();
    expect(storage.stored, isNull);
  });

  test('a restored session is picked up as the starting state', () {
    final storage = _MemoryStorage();
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith((ref) => _TestAuth()),
        liveSessionStorageProvider.overrideWithValue(storage),
        restoredLiveSessionProvider.overrideWithValue(
          PersistedLiveSession(session: session, ownerId: 3),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(liveActivityProvider)!.exercises, hasLength(1));
  });

  test("a different account logging in drops the previous account's workout", () {
    final auth = _TestAuth();
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith((ref) => auth),
        restoredLiveSessionProvider.overrideWithValue(
          PersistedLiveSession(session: session, ownerId: 3),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(liveActivityProvider), isNotNull);

    // Same account: kept.
    auth.signInAs(
      const AuthAuthenticated(
        token: 't',
        user: User(id: 3, email: 'a@example.com', isAdmin: false),
      ),
    );
    expect(container.read(liveActivityProvider), isNotNull);

    auth.signInAs(
      const AuthAuthenticated(
        token: 't',
        user: User(id: 4, email: 'b@example.com', isAdmin: false),
      ),
    );
    expect(container.read(liveActivityProvider), isNull);
  });
}
