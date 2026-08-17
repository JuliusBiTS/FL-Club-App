import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_screen.dart';
import '../../features/events/presentation/event_detail_screen.dart';
import '../../features/events/presentation/events_feed_screen.dart';
import '../../features/loyalty/loyalty_screen.dart';
import '../../features/membership/membership_interest_screen.dart';
import '../../features/podcast/podcast_screen.dart';
import '../../features/read/read_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/tickets/tickets_screen.dart';
import '../auth/profile_provider.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Route map — briefing §9.0. Guests see every tab; nothing here forces
/// sign-in on launch (no onboarding carousel, no wall — actions that need
/// an account trigger a sign-in sheet at the point of need, once M2 adds
/// it). /scan is redirect-guarded here as a UX nicety; the real gate is
/// server-side on every scan call (§9.11/§13.5).
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/events',
    refreshListenable: _ProfileRefreshListenable(ref),
    redirect: (context, state) {
      final isStaff = ref.read(currentProfileProvider).valueOrNull?.isStaff ?? false;
      if (state.matchedLocation == '/scan' && !isStaff) {
        return '/events';
      }
      return null;
    },
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/events',
                builder: (context, state) => const EventsFeedScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: ':slug',
                    builder: (context, state) => EventDetailScreen(slug: state.pathParameters['slug']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[GoRoute(path: '/podcast', builder: (context, state) => const PodcastScreen())],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[GoRoute(path: '/read', builder: (context, state) => const ReadScreen())],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/you',
                builder: (context, state) => const AccountScreen(),
                routes: <RouteBase>[
                  GoRoute(path: 'tickets', builder: (context, state) => const TicketsScreen()),
                  GoRoute(path: 'loyalty', builder: (context, state) => const LoyaltyScreen()),
                  GoRoute(path: 'become-a-member', builder: (context, state) => const MembershipInterestScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[GoRoute(path: '/scan', builder: (context, state) => const ScannerScreen())],
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod's profile state into go_router's Listenable-based
/// refresh mechanism, so the /scan redirect re-evaluates the moment
/// member/staff status changes rather than only on the next navigation.
class _ProfileRefreshListenable extends ChangeNotifier {
  _ProfileRefreshListenable(Ref ref) {
    ref.listen(currentProfileProvider, (_, __) => notifyListeners());
  }
}
