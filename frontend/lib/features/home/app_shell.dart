import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'live_workout_banner.dart';

/// Hosts the 5 top-level sections behind a single bottom nav bar, each with
/// its own independent navigation stack (`StatefulShellRoute.indexedStack`
/// in `core/router.dart`) -- switching tabs doesn't lose your place in the
/// others.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiveWorkoutBanner(currentPath: GoRouterState.of(context).uri.path),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.fitness_center), label: 'Exercises'),
              NavigationDestination(icon: Icon(Icons.list_alt), label: 'Routines'),
              NavigationDestination(icon: Icon(Icons.history), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.straighten), label: 'Measurements'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ],
      ),
    );
  }
}
