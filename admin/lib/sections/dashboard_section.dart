import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A quick "how are we doing" page: a handful of live numbers, each one a
/// plain count or sum straight from the database. Nothing here changes data.
class DashboardSection extends StatefulWidget {
  const DashboardSection({super.key});

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _Stats {
  const _Stats({
    required this.upcomingEvents,
    required this.ticketsSoldToday,
    required this.revenueThisMonthMinor,
    required this.activeMembers,
    required this.appliedMembers,
    required this.registeredUsers,
    required this.failedPayments,
  });

  final int upcomingEvents;
  final int ticketsSoldToday;
  final int revenueThisMonthMinor;
  final int activeMembers;
  final int appliedMembers;
  final int registeredUsers;
  final int failedPayments;
}

class _DashboardSectionState extends State<DashboardSection> {
  late Future<_Stats> _stats = _load();

  Future<_Stats> _load() async {
    final SupabaseClient db = Supabase.instance.client;
    final DateTime now = DateTime.now();
    final String startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final String startOfMonth = DateTime(now.year, now.month).toUtc().toIso8601String();
    final String nowIso = now.toUtc().toIso8601String();
    final String weekAgo = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();

    Future<int> count(PostgrestFilterBuilder<dynamic> q) async => (await q.count(CountOption.exact)).count;

    final results = await Future.wait<Object>(<Future<Object>>[
      count(db.from('events').select('id').eq('status', 'published').gte('starts_at', nowIso)),
      count(db.from('tickets').select('id').gte('created_at', startOfDay)),
      db.from('orders').select('total_minor').eq('status', 'paid').gte('created_at', startOfMonth),
      count(db.from('profiles').select('id').eq('member_status', 'active').isFilter('deleted_at', null)),
      count(db.from('profiles').select('id').eq('member_status', 'applied').isFilter('deleted_at', null)),
      count(db.from('profiles').select('id').isFilter('deleted_at', null)),
      count(db.from('orders').select('id').eq('status', 'failed').gte('created_at', weekAgo)),
    ]);

    final List paid = results[2] as List;
    return _Stats(
      upcomingEvents: results[0] as int,
      ticketsSoldToday: results[1] as int,
      revenueThisMonthMinor: paid.fold<int>(0, (int sum, dynamic r) => sum + ((r['total_minor'] as num?)?.toInt() ?? 0)),
      activeMembers: results[3] as int,
      appliedMembers: results[4] as int,
      registeredUsers: results[5] as int,
      failedPayments: results[6] as int,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Dashboard', style: Theme.of(context).textTheme.headlineMedium),
            const Spacer(),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: () => setState(() => _stats = _load())),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<_Stats>(
          future: _stats,
          builder: (BuildContext context, AsyncSnapshot<_Stats> snap) {
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            if (snap.hasError) return const Text("Couldn't load the numbers. Try refreshing.");
            final _Stats s = snap.data!;
            final NumberFormat money = NumberFormat.currency(locale: 'en_GB', symbol: '£');
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: <Widget>[
                _Tile('Upcoming events', '${s.upcomingEvents}', Icons.event_outlined),
                _Tile('Tickets sold today', '${s.ticketsSoldToday}', Icons.confirmation_number_outlined),
                _Tile('Revenue this month', money.format(s.revenueThisMonthMinor / 100), Icons.payments_outlined),
                _Tile('Active members', '${s.activeMembers}', Icons.badge_outlined),
                _Tile('Applied to join', '${s.appliedMembers}', Icons.mark_email_unread_outlined),
                _Tile('Registered people', '${s.registeredUsers}', Icons.people_outline),
                _Tile('Failed payments (7 days)', '${s.failedPayments}', Icons.error_outline),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 22),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
