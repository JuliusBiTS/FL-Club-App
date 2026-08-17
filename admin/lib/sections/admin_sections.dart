import 'package:flutter/material.dart';

/// One placeholder per briefing §9.12 admin console section. Events is
/// first up for real implementation (it unblocks the mobile app's M1 feed
/// having anything to show beyond seed data) — the rest follow roughly in
/// README milestone order. Each of these becomes its own file with a real
/// data table / form once its milestone starts; kept together here for now
/// purely to avoid a wall of near-empty files before there's anything to
/// put in them.
class AdminSectionPlaceholder extends StatelessWidget {
  const AdminSectionPlaceholder({required this.title, required this.description, super.key});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

const dashboardSection = AdminSectionPlaceholder(
  title: 'Dashboard',
  description: 'Upcoming events, tickets sold today, revenue this month, pending membership applications, recent failed payments.',
);

const eventsSection = AdminSectionPlaceholder(
  title: 'Events',
  description: 'Create/edit/publish/cancel events, manage ticket types, split capacity between app and Eventbrite, duplicate a recurring format.',
);

const attendeesSection = AdminSectionPlaceholder(
  title: 'Attendees',
  description: 'Per-event list, export CSV, live check-in status.',
);

const membersSection = AdminSectionPlaceholder(
  title: 'Members',
  description: 'List, filter by status, activate/suspend/renew, upload or replace member photo, set tier and expiry, generate membership number and PIN.',
);

const applicationsSection = AdminSectionPlaceholder(
  title: 'Applications',
  description: 'The membership-apply queue — approve/reject with notes.',
);

const loyaltySection = AdminSectionPlaceholder(
  title: 'Loyalty',
  description: "View any user's ledger, grant a manual adjustment (mandatory reason, written to audit_log).",
);

const staffSection = AdminSectionPlaceholder(
  title: 'Staff',
  description: 'Grant/revoke the staff role.',
);

const contentSection = AdminSectionPlaceholder(
  title: 'Content',
  description: 'Trigger a podcast or WordPress resync, view sync errors.',
);

const auditLogSection = AdminSectionPlaceholder(
  title: 'Audit log',
  description: 'Filterable, read-only — every privileged mutation in the system.',
);
