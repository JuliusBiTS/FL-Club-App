import 'package:supabase_flutter/supabase_flutter.dart';

/// One calendar day of sales (London time).
class DayPoint {
  const DayPoint(this.day, this.tickets, this.revenueMinor);

  final DateTime day;
  final int tickets;
  final int revenueMinor;
}

DateTime _day(String s) {
  final List<String> p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

List<DayPoint> _days(Object? raw) => <DayPoint>[
      for (final dynamic d in (raw as List<dynamic>? ?? const <dynamic>[]))
        DayPoint(_day(d['day'] as String), _int(d['tickets']), _int(d['revenue_minor'])),
    ];

/// Every day from [from] to [to] inclusive, with zeros where nothing sold —
/// so a quiet week shows as a flat line, not a line that skips it.
List<DayPoint> fillDays(List<DayPoint> sparse, DateTime from, DateTime to) {
  final Map<DateTime, DayPoint> byDay = <DateTime, DayPoint>{
    for (final DayPoint p in sparse) DateTime(p.day.year, p.day.month, p.day.day): p,
  };
  final DateTime start = DateTime(from.year, from.month, from.day);
  final DateTime end = DateTime(to.year, to.month, to.day);
  final List<DayPoint> out = <DayPoint>[];
  for (DateTime d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    out.add(byDay[d] ?? DayPoint(d, 0, 0));
  }
  return out;
}

/// Running total across [days] (tickets or revenue).
List<(DateTime, double)> runningTotal(List<DayPoint> days, {required bool revenue}) {
  double sum = 0;
  return <(DateTime, double)>[
    for (final DayPoint d in days) (d.day, sum += revenue ? d.revenueMinor / 100 : d.tickets.toDouble()),
  ];
}

class TypeSales {
  const TypeSales({required this.name, required this.priceMinor, required this.quantity, required this.sold, required this.revenueMinor});

  final String name;
  final int priceMinor;
  final int quantity;
  final int sold;
  final int revenueMinor;
}

class SalesOverview {
  const SalesOverview({
    required this.title,
    required this.startsAt,
    required this.capacityTotal,
    required this.capacityApp,
    required this.eventbriteSold,
    required this.sold,
    required this.checkedIn,
    required this.refunded,
    required this.revenueMinor,
    required this.types,
    required this.daily,
  });

  final String title;
  final DateTime startsAt;
  final int capacityTotal;
  final int capacityApp;
  final int eventbriteSold;
  final int sold;
  final int checkedIn;
  final int refunded;
  final int revenueMinor;
  final List<TypeSales> types;
  final List<DayPoint> daily;

  int get totalSold => sold + eventbriteSold;
  int get remaining => capacityTotal <= 0 ? 0 : (capacityTotal - totalSold).clamp(0, capacityTotal);
  double get averageTicketMinor => sold == 0 ? 0 : revenueMinor / sold;

  factory SalesOverview.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> e = Map<String, dynamic>.from(j['event'] as Map? ?? const <String, dynamic>{});
    final Map<String, dynamic> t = Map<String, dynamic>.from(j['totals'] as Map? ?? const <String, dynamic>{});
    return SalesOverview(
      title: (e['title'] as String?) ?? 'Event',
      startsAt: DateTime.tryParse((e['starts_at'] as String?) ?? '') ?? DateTime.now(),
      capacityTotal: _int(e['capacity_total']),
      capacityApp: _int(e['capacity_app']),
      eventbriteSold: _int(e['eventbrite_sold']),
      sold: _int(t['sold']),
      checkedIn: _int(t['checked_in']),
      refunded: _int(t['refunded']),
      revenueMinor: _int(t['revenue_minor']),
      types: <TypeSales>[
        for (final dynamic x in (j['types'] as List<dynamic>? ?? const <dynamic>[]))
          TypeSales(
            name: x['name'] as String,
            priceMinor: _int(x['price_minor']),
            quantity: _int(x['quantity']),
            sold: _int(x['sold']),
            revenueMinor: _int(x['revenue_minor']),
          ),
      ],
      daily: _days(j['daily']),
    );
  }
}

class UpcomingFill {
  const UpcomingFill(this.title, this.startsAt, this.sold, this.capacity);

  final String title;
  final DateTime startsAt;
  final int sold;
  final int capacity;
}

class DashboardOverview {
  const DashboardOverview({required this.daily, required this.monthly, required this.newMembers, required this.upcoming});

  final List<DayPoint> daily;

  /// 'YYYY-MM' -> (tickets, revenue pence)
  final List<(String, int, int)> monthly;
  final List<(String, int)> newMembers;
  final List<UpcomingFill> upcoming;

  factory DashboardOverview.fromJson(Map<String, dynamic> j) => DashboardOverview(
        daily: _days(j['daily']),
        monthly: <(String, int, int)>[
          for (final dynamic m in (j['monthly'] as List<dynamic>? ?? const <dynamic>[])) (m['month'] as String, _int(m['tickets']), _int(m['revenue_minor'])),
        ],
        newMembers: <(String, int)>[
          for (final dynamic m in (j['members_monthly'] as List<dynamic>? ?? const <dynamic>[])) (m['month'] as String, _int(m['new_members'])),
        ],
        upcoming: <UpcomingFill>[
          for (final dynamic u in (j['upcoming'] as List<dynamic>? ?? const <dynamic>[]))
            UpcomingFill(u['title'] as String, DateTime.parse(u['starts_at'] as String), _int(u['sold']), _int(u['capacity'])),
        ],
      );
}

/// The last [count] calendar months up to this one as 'YYYY-MM', so a month with
/// no sales still gets a (zero) bar.
List<String> lastMonths(int count, {DateTime? now}) {
  final DateTime n = now ?? DateTime.now();
  return <String>[
    for (int i = count - 1; i >= 0; i--)
      () {
        final DateTime d = DateTime(n.year, n.month - i);
        return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      }(),
  ];
}

class OverviewRepository {
  OverviewRepository([SupabaseClient? client]) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<DashboardOverview> dashboard() async {
    final dynamic r = await _client.rpc('dashboard_overview');
    return DashboardOverview.fromJson(Map<String, dynamic>.from(r as Map));
  }

  Future<SalesOverview> eventSales(String eventId) async {
    final dynamic r = await _client.rpc('event_sales_overview', params: <String, dynamic>{'p_event_id': eventId});
    return SalesOverview.fromJson(Map<String, dynamic>.from(r as Map));
  }
}
