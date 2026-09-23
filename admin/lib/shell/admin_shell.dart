import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_gate.dart';
import '../sections/audit_log_section.dart';
import '../sections/dashboard_section.dart';
import '../sections/orders_section.dart';

/// Desktop-first console shell — briefing §9.12. Wide NavigationRail
/// rather than the mobile app's bottom nav; this runs in a browser tab on
/// a desk, not a phone in a hand.
///
/// Admins get every section. Staff get the two they need day to day —
/// Events and Notifications — everything else is hidden here AND refused by
/// the database, so a staff account can't reach it by any route.
class AdminShell extends StatefulWidget {
  const AdminShell({required this.isAdmin, super.key});

  final bool isAdmin;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  late final EventAdminRepository _events = EventAdminRepository(Supabase.instance.client);
  late final ArticleAdminRepository _articles = ArticleAdminRepository(Supabase.instance.client);
  late final UserAdminRepository _users = UserAdminRepository(Supabase.instance.client);
  late final MediaAdminRepository _media = MediaAdminRepository(Supabase.instance.client);

  // Admins get the full menu; staff get Events and Notifications only.
  // (Attendees, Loyalty and Applications used to be empty placeholders and
  // are gone: attendee lists live with each event, "applied to join" is a
  // filter under People, and Users/Members/Staff are one People screen.)
  late final List<(String, IconData, Widget)> _sections = <(String, IconData, Widget)>[
    if (widget.isAdmin) ('Dashboard', Icons.dashboard_outlined, const DashboardSection()),
    ('Events', Icons.event_outlined, EventsManagerScreen(repository: _events, isAdmin: widget.isAdmin, embedded: true)),
    if (widget.isAdmin) ('Orders', Icons.receipt_long_outlined, const OrdersSection()),
    if (widget.isAdmin)
      (
        'People',
        Icons.people_outline,
        UsersScreen(
          repository: _users,
          embedded: true,
          title: 'People',
          description:
              'Everyone who has registered. Open a person to make them a member, staff or an admin — they need to have registered first. '
              'Use the filters for members, staff and admins, and people who have applied to join.',
        ),
      ),
    if (widget.isAdmin)
      (
        'Articles',
        Icons.article_outlined,
        ArticlesManagerScreen(repository: _articles, imageRepository: _events, embedded: true),
      ),
    if (widget.isAdmin) ('Media', Icons.video_library_outlined, MediaContentScreen(repository: _media, embedded: true)),
    ('Notifications', Icons.notifications_outlined, NotificationsScreen(repository: _events, embedded: true)),
    if (widget.isAdmin) ('Audit log', Icons.history_outlined, const AuditLogSection()),
  ];

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    // Back to the sign-in screen.
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AdminAuthGate()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            extended: MediaQuery.of(context).size.width > 900,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              // A neutral monogram until the club supplies a logo file — docs/OPEN_QUESTIONS.md.
              child: CircleAvatar(
                radius: 20,
                backgroundColor: FlcColors.brand,
                child: Text('FC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: _signOut),
                ),
              ),
            ),
            destinations: <NavigationRailDestination>[
              for (final section in _sections)
                NavigationRailDestination(icon: Icon(section.$2), label: Text(section.$1)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _sections[_selectedIndex].$3),
        ],
      ),
    );
  }
}
