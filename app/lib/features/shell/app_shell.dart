import 'package:flc_core/flc_core.dart'; // isStaff is an extension getter — needs the declaring library in scope
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/profile_provider.dart';
import '../../core/preferences/membership_card_preferences.dart';
import '../../core/ui/membership_handle_visibility.dart';
import '../membership/membership_card_handle.dart';
import '../podcast/podcast_providers.dart';

/// Fixed regardless of staff/non-staff — Scan is only ever appended at the
/// end, never inserted before this — see app_router.dart's branch order.
const int _kListenTabIndex = 1;

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

    // Computed fresh every build from live signals, never an imperative
    // set/reset flag — see membership_handle_visibility.dart for why that
    // distinction is what actually fixes the old "gone for the rest of the
    // session" bug (it can't get stuck, because nothing is ever "left set").
    final bool modalClaimsWholeBar = !ref.watch(showMembershipHandleProvider);
    final bool onListenTabWithAudio =
        navigationShell.currentIndex == _kListenTabIndex && ref.watch(currentMediaItemProvider).valueOrNull != null;
    final bool userPrefersDot = ref.watch(alwaysShowDotProvider);
    final MembershipHandleMode handleMode = modalClaimsWholeBar
        ? MembershipHandleMode.hidden
        : (onListenTabWithAudio || userPrefersDot)
            ? MembershipHandleMode.dot
            : MembershipHandleMode.full;

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: 'Events',
      ),
      const NavigationDestination(
        icon: Icon(Icons.perm_media_outlined),
        selectedIcon: Icon(Icons.perm_media),
        label: 'Media',
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
          // Positioned.fill (not just a bottom strip) so the drag-to-reveal
          // card has the full height to expand into — MembershipCardHandle
          // only actually paints/hit-tests within its own current extent
          // (or nothing, in hidden mode), so this doesn't block taps on
          // navigationShell above it.
          Positioned.fill(child: MembershipCardHandle(activeTabIndex: navigationShell.currentIndex, mode: handleMode)),
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
