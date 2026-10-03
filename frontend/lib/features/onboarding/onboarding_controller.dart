import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_steps.dart';

/// Remembers, per account, that the first-run tour has been completed or
/// dismissed, so it isn't offered again on every login. Best effort: a
/// failure to read or write must never get in the way of using the app.
abstract class OnboardingStorage {
  Future<bool> hasSeen(int userId);

  Future<void> markSeen(int userId);
}

class PrefsOnboardingStorage implements OnboardingStorage {
  const PrefsOnboardingStorage();

  static String _key(int userId) => 'onboarding_seen_$userId';

  @override
  Future<bool> hasSeen(int userId) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key(userId)) ?? false;
    } catch (error) {
      // Can't tell: erring on "seen" means a broken store never nags anyone.
      debugPrint('Could not read the onboarding flag: $error');
      return true;
    }
  }

  @override
  Future<void> markSeen(int userId) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key(userId), true);
    } catch (error) {
      debugPrint('Could not persist the onboarding flag: $error');
    }
  }
}

final onboardingStorageProvider = Provider<OnboardingStorage>(
  (ref) => const PrefsOnboardingStorage(),
);

final tourStepsProvider = Provider<List<TourStep>>((ref) => defaultTourSteps);

class OnboardingState {
  const OnboardingState({this.stepIndex});

  /// Which step is showing; null while no tour is running.
  final int? stepIndex;

  bool get active => stepIndex != null;
}

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController(this._storage, this._steps) : super(const OnboardingState());

  final OnboardingStorage _storage;
  final List<TourStep> _steps;
  int? _userId;

  List<TourStep> get steps => _steps;

  TourStep? get currentStep {
    final index = state.stepIndex;
    return index == null ? null : _steps[index];
  }

  /// Starts the tour for [userId] unless they have already seen it.
  Future<void> userSignedIn(int userId) async {
    if (_userId == userId) return;
    _userId = userId;
    final seen = await _storage.hasSeen(userId);
    if (mounted && _userId == userId && !seen) {
      state = const OnboardingState(stepIndex: 0);
    }
  }

  /// Ends any running tour without recording it as seen -- the next account
  /// to sign in on this device gets its own.
  void userSignedOut() {
    _userId = null;
    state = const OnboardingState();
  }

  /// From the top, whether or not it was seen before (Settings' "Take the tour again").
  void restart() => state = const OnboardingState(stepIndex: 0);

  void next() {
    final index = state.stepIndex;
    if (index == null) return;
    if (index + 1 >= _steps.length) {
      finish();
    } else {
      state = OnboardingState(stepIndex: index + 1);
    }
  }

  /// Closes the tour -- finished, or dismissed halfway -- and remembers it.
  void finish() {
    state = const OnboardingState();
    final userId = _userId;
    if (userId != null) _storage.markSeen(userId);
  }

  /// Something the tour may be waiting for just happened.
  void event(String name) {
    if (currentStep?.advanceOnEvent == name) next();
  }

  /// The app navigated to [path].
  void locationChanged(String path) {
    if (currentStep?.advanceOnLocation?.call(path) ?? false) next();
  }
}

final onboardingProvider = StateNotifierProvider<OnboardingController, OnboardingState>(
  (ref) => OnboardingController(ref.watch(onboardingStorageProvider), ref.watch(tourStepsProvider)),
);

/// What an `OnboardingTarget` registers itself as, so the overlay can find
/// where on screen it currently is.
abstract class TourTargetHandle {
  BuildContext get context;

  /// False while the target sits in a branch or route that isn't the one
  /// showing (an `IndexedStack` keeps inactive tabs alive, laid out
  /// somewhere, but never painted).
  bool get isShowing;
}

/// Which on-screen things each target id currently names. An id may be
/// registered more than once -- the wide layout's navigation rail is a
/// separate icon and label per destination, and the spotlight covers both.
class TourTargetRegistry {
  final Map<String, Set<TourTargetHandle>> _targets = {};

  void register(String id, TourTargetHandle handle) =>
      _targets.putIfAbsent(id, () => {}).add(handle);

  void unregister(String id, TourTargetHandle handle) => _targets[id]?.remove(handle);

  /// The smallest rectangle (in global coordinates) around every showing
  /// handle for [id], or null if there is none.
  Rect? boundsOf(String id, {void Function(BuildContext context, Rect rect)? onFound}) {
    Rect? bounds;
    for (final handle in _targets[id] ?? const <TourTargetHandle>{}) {
      if (!handle.isShowing) continue;
      final object = handle.context.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) continue;
      final rect = object.localToGlobal(Offset.zero) & object.size;
      onFound?.call(handle.context, rect);
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }
    return bounds;
  }
}

final tourTargetRegistryProvider = Provider<TourTargetRegistry>((ref) => TourTargetRegistry());
