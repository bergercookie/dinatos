import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_notifier.dart';
import 'live_workout_banner.dart';

/// Viewport width from which the shell swaps the bottom nav bar for a side
/// rail (a desktop browser window or the Linux app, not a phone).
const double _wideBreakpoint = 900;

const _destinations = [
  (icon: Icons.fitness_center, label: 'Exercises'),
  (icon: Icons.list_alt, label: 'Routines'),
  (icon: Icons.history, label: 'Home'),
  (icon: Icons.straighten, label: 'Measurements'),
  (icon: Icons.person, label: 'Profile'),
];

/// Hosts the 5 top-level sections behind a single nav (bottom bar on narrow
/// screens, side rail with a log-out button on wide ones), each with its own
/// independent navigation stack (`StatefulShellRoute.indexedStack` in
/// `core/router.dart`) -- switching tabs doesn't lose your place in the
/// others.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = LiveWorkoutBanner(
      currentPath: GoRouterState.of(context).uri.path,
    );

    if (MediaQuery.sizeOf(context).width >= _wideBreakpoint) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      tooltip: 'Log out',
                      icon: const Icon(Icons.logout),
                      onPressed: () =>
                          ref.read(authNotifierProvider.notifier).logout(),
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: navigationShell),
                  banner,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          banner,
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _goBranch,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.icon), label: d.label),
            ],
          ),
        ],
      ),
    );
  }
}
