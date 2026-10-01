import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/overview_data.dart';
import '../widgets/admin_charts.dart';

/// "How are we doing": the headline numbers, then charts for the last month,
/// the last year, membership and how full the next events are. Nothing here
/// changes data.
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

class _Everything {
  const _Everything(this.stats, this.charts);

  final _Stats stats;

  /// Null if the charts query failed — the tiles still show.
  final DashboardOverview? charts;
}

class _DashboardSectionState extends State<DashboardSection> {
  late Future<_Everything> _data = _load();

  Future<_Stats> _loadStats() async {
    final SupabaseClient db = Supabase.instance.client;
    final DateTime now = DateTime.now();
    final String startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final String startOfMonth = DateTime(now.year, now.month).toUtc().toIso8601String();
    final String nowIso = now.toUtc().toIso8601String();
    final String weekAgo = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();

    Future<int> count(PostgrestFilterBuilder<dynamic> q) async => (await q.count(CountOption.exact)).count;

    final List<Object> results = await Future.wait<Object>(<Future<Object>>[
      count(db.from('events').select('id').eq('status', 'published').gte('starts_at', nowIso)),
      count(db.from('tickets').select('id').gte('created_at', startOfDay)),
      db.from('orders').select('total_minor').eq('status', 'paid').gte('created_at', startOfMonth),
      count(db.from('profiles').select('id').eq('member_status', 'active').isFilter('deleted_at', null)),
      count(db.from('profiles').select('id').eq('member_status', 'applied').isFilter('deleted_at', null)),
      count(db.from('profiles').select('id').isFilter('deleted_at', null)),
      count(db.from('orders').select('id').eq('status', 'failed').gte('created_at', weekAgo)),
    ]);

    final List<dynamic> paid = results[2] as List<dynamic>;
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

  Future<_Everything> _load() async {
    final Future<_Stats> stats = _loadStats();
    DashboardOverview? charts;
    try {
      charts = await OverviewRepository().dashboard();
    } catch (_) {
      charts = null;
    }
    return _Everything(await stats, charts);
  }

  static final NumberFormat _money = NumberFormat.currency(locale: 'en_GB', symbol: '£');

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Dashboard', style: Theme.of(context).textTheme.headlineMedium),
            const Spacer(),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: () => setState(() => _data = _load())),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<_Everything>(
          future: _data,
          builder: (BuildContext context, AsyncSnapshot<_Everything> snap) {
            if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
            if (snap.hasError) return const Text("Couldn't load the numbers. Try refreshing.");
            final _Stats s = snap.data!.stats;
            final DashboardOverview? c = snap.data!.charts;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: <Widget>[
                    StatTile(label: 'Upcoming events', value: '${s.upcomingEvents}', icon: Icons.event_outlined),
                    StatTile(label: 'Tickets sold today', value: '${s.ticketsSoldToday}', icon: Icons.confirmation_number_outlined),
                    StatTile(label: 'Revenue this month', value: _money.format(s.revenueThisMonthMinor / 100), icon: Icons.payments_outlined),
                    StatTile(label: 'Active members', value: '${s.activeMembers}', icon: Icons.badge_outlined),
                    StatTile(label: 'Applied to join', value: '${s.appliedMembers}', icon: Icons.mark_email_unread_outlined),
                    StatTile(label: 'Registered people', value: '${s.registeredUsers}', icon: Icons.people_outline),
                    StatTile(label: 'Failed payments (7 days)', value: '${s.failedPayments}', icon: Icons.error_outline),
                  ],
                ),
                const SizedBox(height: 24),
                if (c == null)
                  const Text("The charts couldn't load just now — the numbers above are still right. Try refreshing.")
                else
                  _charts(context, c),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _charts(BuildContext context, DashboardOverview c) {
    final DateTime today = DateTime.now();
    final List<DayPoint> days = fillDays(c.daily, today.subtract(const Duration(days: 29)), today);
    final List<String> months = lastMonths(12);
    final Map<String, (int, int)> monthly = <String, (int, int)>{for (final (String, int, int) m in c.monthly) m.$1: (m.$2, m.$3)};
    final Map<String, int> joined = <String, int>{for (final (String, int) m in c.newMembers) m.$1: m.$2};
    String monthLabel(String ym) => DateFormat('MMM').format(DateTime(int.parse(ym.substring(0, 4)), int.parse(ym.substring(5))));

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        const double gap = 16;
        final double half = box.maxWidth > 980 ? (box.maxWidth - gap) / 2 : box.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            ChartCard(
              width: half,
              title: 'Tickets sold',
              subtitle: 'Last 30 days',
              child: AdminBarChart(
                bars: <(String, double)>[for (final DayPoint d in days) (DateFormat('d MMM').format(d.day), d.tickets.toDouble())],
                format: (double v) => '${v.round()} ticket${v.round() == 1 ? '' : 's'}',
              ),
            ),
            ChartCard(
              width: half,
              title: 'Revenue by month',
              subtitle: 'Last 12 months, ticket sales',
              child: AdminBarChart(
                bars: <(String, double)>[for (final String m in months) (monthLabel(m), (monthly[m]?.$2 ?? 0) / 100)],
                format: (double v) => _money.format(v),
              ),
            ),
            ChartCard(
              width: half,
              title: 'New members',
              subtitle: 'Joined per month, last 12 months',
              child: AdminBarChart(
                bars: <(String, double)>[for (final String m in months) (monthLabel(m), (joined[m] ?? 0).toDouble())],
                format: (double v) => '${v.round()} new member${v.round() == 1 ? '' : 's'}',
              ),
            ),
            ChartCard(
              width: half,
              title: 'Next events — how full',
              subtitle: 'Tickets sold against capacity',
              child: c.upcoming.isEmpty
                  ? const EmptyChart('No upcoming events.')
                  : Column(
                      children: <Widget>[
                        for (final UpcomingFill u in c.upcoming)
                          FillBar(label: '${u.title} · ${DateFormat('d MMM').format(u.startsAt.toLocal())}', value: u.sold, of: u.capacity),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
