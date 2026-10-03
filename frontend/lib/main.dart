import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_notifier.dart';
import 'core/auth/auth_state.dart';
import 'core/insecure_tls_provider.dart';
import 'core/insecure_tls_storage.dart';
import 'core/router.dart';
import 'core/server_url_provider.dart';
import 'core/server_url_storage.dart';
import 'core/theme.dart';
import 'core/theme_mode_provider.dart';
import 'features/activities/live/live_session.dart';
import 'features/activities/live/live_session_storage.dart';
import 'features/activities/live/live_workout_notification.dart';
import 'features/onboarding/onboarding_overlay.dart';

/// A catch-all route so this renders regardless of the browser's current
/// URL -- see the `AuthUnknown` branch below for why that matters.
final _loadingRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/:path(.*)',
      builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  ],
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read before runApp(), not through the providers' own async machinery:
  // dioProvider (and everything built on it, auth included) needs the real
  // server URL and TLS setting from their very first read, not a
  // build-time default that then flips underneath it a moment later.
  final storedServerUrl = await ServerUrlStorage().read();
  final storedAllowInsecureTls = await InsecureTlsStorage().read();
  final storedThemeMode = await const ThemeModeStorage().read();
  const liveSessionStorage = PrefsLiveSessionStorage();
  final restoredLiveSession = await liveSessionStorage.read();
  runApp(
    ProviderScope(
      overrides: [
        liveSessionStorageProvider.overrideWithValue(liveSessionStorage),
        restoredLiveSessionProvider.overrideWithValue(restoredLiveSession),
        if (storedServerUrl != null) serverUrlProvider.overrideWith((ref) => storedServerUrl),
        allowInsecureTlsProvider.overrideWith((ref) => storedAllowInsecureTls),
        themeModeProvider.overrideWith((ref) => storedThemeMode),
      ],
      child: const DinatosApp(),
    ),
  );
}

class DinatosApp extends ConsumerWidget {
  const DinatosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    ref.watch(liveWorkoutNotificationSyncProvider);

    if (authState is AuthUnknown) {
      // A plain `MaterialApp(home: ...)` here (Navigator 1.0) throws "Could
      // not navigate to initial route" on web reload whenever the browser's
      // URL isn't "/" (e.g. it was last on "/login" and got refreshed): that
      // widget has no route table at all, but web still hands it the
      // current URL path as `initialRoute` to resolve. `MaterialApp.router`
      // with a catch-all route sidesteps the whole mechanism -- it renders
      // the same spinner regardless of path, without ever trying to look
      // one up in a route table that doesn't exist.
      return MaterialApp.router(
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeMode,
        routerConfig: _loadingRouter,
      );
    }

    return MaterialApp.router(
      title: 'Dinatos',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => OnboardingOverlay(router: router, child: child!),
    );
  }
}
