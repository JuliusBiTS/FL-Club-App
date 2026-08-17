import 'package:flutter/material.dart';

import '../sections/admin_sections.dart';
import '../sections/orders_section.dart';

/// Desktop-first console shell — briefing §9.12. Wide NavigationRail
/// rather than the mobile app's bottom nav; this runs in a browser tab on
/// a desk, not a phone in a hand.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  static const _sections = <(String, IconData, Widget)>[
    ('Dashboard', Icons.dashboard_outlined, dashboardSection),
    ('Events', Icons.event_outlined, eventsSection),
    ('Orders', Icons.receipt_long_outlined, OrdersSection()),
    ('Attendees', Icons.groups_outlined, attendeesSection),
    ('Members', Icons.badge_outlined, membersSection),
    ('Applications', Icons.mark_email_unread_outlined, applicationsSection),
    ('Loyalty', Icons.loyalty_outlined, loyaltySection),
    ('Staff', Icons.admin_panel_settings_outlined, staffSection),
    ('Content', Icons.sync_outlined, contentSection),
    ('Audit log', Icons.history_outlined, auditLogSection),
  ];

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
              child: FlutterLogo(size: 32), // TODO: club mark, once available — docs/OPEN_QUESTIONS.md
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
