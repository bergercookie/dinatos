import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_notifier.dart';
import '../onboarding/onboarding_overlay.dart';
import 'live_workout_banner.dart';

/// Viewport width from which the shell swaps the bottom nav bar for a side
/// rail (a desktop browser window or the Linux app, not a phone).
const double _wideBreakpoint = 900;

const _destinations = [
  (icon: Icons.fitness_center, label: 'Exercises'),
  (icon: Icons.list_alt, label: 'Routines'),
  (icon: Icons.home, label: 'Home'),
  (icon: Icons.straighten, label: 'Measurements'),
  (icon: Icons.person, label: 'Profile'),
];

/// What the first-run tour calls a tab: `tab-home`, `tab-profile`, ...
String _tabTarget(String label) => 'tab-${label.toLowerCase()}';

/// Hosts the 5 top-level sections behind a single nav (bottom bar on narrow
/// screens, side rail with a log-out button on wide ones), each with its own
/// independent navigation stack (`StatefulShellRoute.indexedStack` in
/// `core/router.dart`) -- switching tabs doesn't lose your place in the
/// others.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) =>
      navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = LiveWorkoutBanner(currentPath: GoRouterState.of(context).uri.path);

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
                  // Icon and label are both registered, so the tour's spotlight
                  // covers the whole destination, not just its icon.
                  NavigationRailDestination(
                    icon: OnboardingTarget(id: _tabTarget(d.label), child: Icon(d.icon)),
                    label: OnboardingTarget(id: _tabTarget(d.label), child: Text(d.label)),
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
                      onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
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
                OnboardingTarget(
                  id: _tabTarget(d.label),
                  child: NavigationDestination(icon: Icon(d.icon), label: d.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
