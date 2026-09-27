import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/activities/activity_form_screen.dart';
import '../features/activities/activity_list_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/exercises/exercise_form_screen.dart';
import '../features/exercises/exercise_list_screen.dart';
import '../features/exercises/exercise_tutorial_screen.dart';
import '../features/home/app_shell.dart';
import '../features/measurements/measurement_form_screen.dart';
import '../features/measurements/measurement_list_screen.dart';
import '../features/imports/hevy_import_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/workouts/workout_form_screen.dart';
import '../features/workouts/workout_list_screen.dart';
import 'auth/auth_notifier.dart';
import 'auth/auth_state.dart';

/// Bridges a Riverpod provider to the `Listenable` go_router's `redirect`
/// wants re-evaluated on -- otherwise a state change (e.g. a 401 flipping
/// [AuthAuthenticated] to [AuthUnauthenticated]) would sit unrouted until
/// the next unrelated navigation.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authNotifierProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshNotifier(ref);
  return GoRouter(
    initialLocation: '/exercises',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final loggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/register';
      if (authState is AuthUnknown) {
        return null;
      }
      if (authState is! AuthAuthenticated) {
        return loggingIn ? null : '/login';
      }
      if (loggingIn) {
        return '/exercises';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/exercises',
                builder: (context, state) => const ExerciseListScreen(),
                routes: [
                  GoRoute(path: 'new', builder: (context, state) => const ExerciseFormScreen()),
                  GoRoute(
                    path: ':id/edit',
                    builder: (context, state) =>
                        ExerciseFormScreen(exerciseId: int.parse(state.pathParameters['id']!)),
                  ),
                  GoRoute(
                    path: ':id/tutorial',
                    builder: (context, state) =>
                        ExerciseTutorialScreen(exerciseId: int.parse(state.pathParameters['id']!)),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/workouts',
                builder: (context, state) => const WorkoutListScreen(),
                routes: [
                  GoRoute(path: 'new', builder: (context, state) => const WorkoutFormScreen()),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        WorkoutFormScreen(workoutId: int.parse(state.pathParameters['id']!)),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activities',
                builder: (context, state) => const ActivityListScreen(),
                routes: [
                  GoRoute(path: 'new', builder: (context, state) => const ActivityFormScreen()),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        ActivityFormScreen(activityId: int.parse(state.pathParameters['id']!)),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/measurements',
                builder: (context, state) => const MeasurementListScreen(),
                routes: [
                  GoRoute(path: 'new', builder: (context, state) => const MeasurementFormScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'import-hevy',
                    builder: (context, state) => const HevyImportScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
