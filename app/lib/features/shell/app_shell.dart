import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/profile_provider.dart';
import '../../core/ui/membership_handle_visibility.dart';
import '../membership/membership_card_handle.dart';

/// Bottom navigation shell — briefing §9.0. Four tabs for everyone, a
/// fifth (Scan) that's simply omitted from the visible destinations for
/// non-staff rather than conditionally routed — the route itself is also
/// redirect-guarded (see app_router.dart) and re-verified server-side on
/// every scan call regardless (§9.11), this is UX only.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isStaff = ref.watch(currentProfileProvider).valueOrNull?.isStaff ?? false;
    final bool showHandle = ref.watch(showMembershipHandleProvider);

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: 'Events',
      ),
      const NavigationDestination(
        icon: Icon(Icons.graphic_eq_outlined),
        selectedIcon: Icon(Icons.graphic_eq),
        label: 'Podcast',
      ),
      const NavigationDestination(
        icon: Icon(Icons.article_outlined),
        selectedIcon: Icon(Icons.article),
        label: 'Read',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'You',
      ),
      if (isStaff)
        const NavigationDestination(
          icon: Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: Icon(Icons.qr_code_scanner),
          label: 'Scan',
        ),
    ];

    return Scaffold(
      body: Stack(
        children: <Widget>[
          navigationShell,
          // Reachable from anywhere in one gesture, opens in <300ms, never
          // needs a network call (briefing §9.6) — sits just above the bar.
          // Hidden while a screen-specific bottom bar (e.g. event detail's
          // "Get tickets") claims the same space — see
          // showMembershipHandleProvider's doc comment. Positioned.fill (not
          // just a bottom strip) so the drag-to-reveal card has the full
          // height to expand into — MembershipCardHandle only actually
          // paints/hit-tests within its own current extent, so this doesn't
          // block taps on navigationShell above the collapsed handle.
          if (showHandle) Positioned.fill(child: MembershipCardHandle(activeTabIndex: navigationShell.currentIndex)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex < destinations.length ? navigationShell.currentIndex : 0,
        onDestinationSelected: (index) =>
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        destinations: destinations,
      ),
    );
  }
}
