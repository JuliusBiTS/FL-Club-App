import 'package:frontline_club_admin/data/overview_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fillDays adds zero days so quiet stretches show as flat', () {
    final List<DayPoint> sparse = <DayPoint>[DayPoint(DateTime(2026, 9, 1), 3, 4500), DayPoint(DateTime(2026, 9, 4), 1, 1500)];
    final List<DayPoint> filled = fillDays(sparse, DateTime(2026, 9, 1), DateTime(2026, 9, 5));
    expect(filled.map((DayPoint d) => d.tickets), <int>[3, 0, 0, 1, 0]);
    expect(filled.map((DayPoint d) => d.day.day), <int>[1, 2, 3, 4, 5]);
  });

  test('runningTotal accumulates tickets and revenue (in pounds)', () {
    final List<DayPoint> days = <DayPoint>[DayPoint(DateTime(2026, 9, 1), 2, 3000), DayPoint(DateTime(2026, 9, 2), 0, 0), DayPoint(DateTime(2026, 9, 3), 1, 1500)];
    expect(runningTotal(days, revenue: false).map(((DateTime, double) p) => p.$2), <double>[2, 2, 3]);
    expect(runningTotal(days, revenue: true).map(((DateTime, double) p) => p.$2), <double>[30, 30, 45]);
  });

  test('lastMonths lists twelve months ending this one, across a year boundary', () {
    final List<String> m = lastMonths(12, now: DateTime(2026, 2, 15));
    expect(m.first, '2025-03');
    expect(m.last, '2026-02');
    expect(m.length, 12);
  });

  test('SalesOverview reads the server answer and works out what is left', () {
    final SalesOverview o = SalesOverview.fromJson(<String, dynamic>{
      'event': <String, dynamic>{'title': 'Panel', 'starts_at': '2026-10-03T17:00:00+00:00', 'capacity_total': 100, 'capacity_app': 80, 'eventbrite_sold': 10},
      'totals': <String, dynamic>{'sold': 30, 'checked_in': 5, 'refunded': 1, 'revenue_minor': 45000},
      'types': <dynamic>[
        <String, dynamic>{'name': 'Standard', 'price_minor': 1500, 'quantity': 70, 'sold': 20, 'revenue_minor': 30000},
        <String, dynamic>{'name': 'Member', 'price_minor': 500, 'quantity': 10, 'sold': 10, 'revenue_minor': 15000},
      ],
      'daily': <dynamic>[
        <String, dynamic>{'day': '2026-09-20', 'tickets': 12, 'revenue_minor': 18000},
      ],
    });
    expect(o.totalSold, 40);
    expect(o.remaining, 60);
    expect(o.averageTicketMinor, 1500);
    expect(o.types.length, 2);
    expect(o.daily.single.day, DateTime(2026, 9, 20));
  });

  test('an empty server answer still parses', () {
    final DashboardOverview d = DashboardOverview.fromJson(<String, dynamic>{});
    expect(d.daily, isEmpty);
    expect(d.upcoming, isEmpty);
  });
}

