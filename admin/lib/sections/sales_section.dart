import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/overview_data.dart';
import '../widgets/admin_charts.dart';

/// Ticket sales for one event, laid out like an Eventbrite report: the headline
/// numbers, how full it is, sales over time, and the split by ticket type.
/// Read-only — nothing on this page changes any data.
class SalesSection extends StatefulWidget {
  const SalesSection({required this.events, OverviewRepository? repository, super.key}) : _repository = repository;

  final EventAdminRepository events;
  final OverviewRepository? _repository;

  @override
  State<SalesSection> createState() => _SalesSectionState();
}

class _SalesSectionState extends State<SalesSection> {
  late final OverviewRepository _repo = widget._repository ?? OverviewRepository();
  late final Future<List<EventModel>> _events = widget.events.listEvents();

  String? _selectedId;
  Future<SalesOverview>? _overview;
  bool _revenue = false;
  bool _running = true;

  static final NumberFormat _money = NumberFormat.currency(locale: 'en_GB', symbol: '£');
  static String pounds(int minor) => _money.format(minor / 100);

  void _select(String id) {
    setState(() {
      _selectedId = id;
      _overview = _repo.eventSales(id);
    });
  }

  /// Next event that hasn't happened, else the most recent one.
  String? _defaultEvent(List<EventModel> events) {
    if (events.isEmpty) return null;
    final DateTime now = DateTime.now();
    final List<EventModel> published = events.where((EventModel e) => e.status == 'published').toList()..sort((EventModel a, EventModel b) => a.startsAt.compareTo(b.startsAt));
    for (final EventModel e in published) {
      if (e.startsAt.isAfter(now)) return e.id;
    }
    return (published.isNotEmpty ? published.last : events.first).id;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EventModel>>(
      future: _events,
      builder: (BuildContext context, AsyncSnapshot<List<EventModel>> snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(32), child: LinearProgressIndicator());
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(32), child: Text("Couldn't load events. ${EventAdminRepository.describeError(snap.error!)}"));
        final List<EventModel> events = (snap.data ?? const <EventModel>[]).toList()..sort((EventModel a, EventModel b) => b.startsAt.compareTo(a.startsAt));
        if (events.isEmpty) return const Padding(padding: EdgeInsets.all(32), child: Text('No events yet.'));
        if (_selectedId == null) {
          final String id = _defaultEvent(events)!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedId == null) _select(id);
          });
        }

        return ListView(
          padding: const EdgeInsets.all(32),
          children: <Widget>[
            Text('Sales', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: FlcSpace.xs),
            Text('Tickets sold and revenue for one event.', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context))),
            const SizedBox(height: FlcSpace.md),
            _picker(events),
            const SizedBox(height: FlcSpace.lg),
            if (_overview == null)
              const LinearProgressIndicator()
            else
              FutureBuilder<SalesOverview>(
                future: _overview,
                builder: (BuildContext context, AsyncSnapshot<SalesOverview> s) {
                  if (s.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                  if (s.hasError) return Text("Couldn't load the numbers. ${EventAdminRepository.describeError(s.error!)}");
                  return _report(context, s.data!);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _picker(List<EventModel> events) {
    final DateFormat fmt = DateFormat('d MMM yyyy');
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DropdownButtonFormField<String>(
          initialValue: _selectedId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Event'),
          items: <DropdownMenuItem<String>>[
            for (final EventModel e in events)
              DropdownMenuItem<String>(
                value: e.id,
                child: Text('${e.title} · ${fmt.format(e.startsAt.toLocal())}${e.status == 'published' ? '' : ' (${e.status})'}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (String? id) {
            if (id != null) _select(id);
          },
        ),
      ),
    );
  }

  Widget _report(BuildContext context, SalesOverview o) {
    final List<Color> palette = chartPalette(context);
    final DateTime today = DateTime.now();
    final DateTime lastSale = o.daily.isEmpty ? today : o.daily.last.day;
    final DateTime firstDay = o.daily.isEmpty ? today.subtract(const Duration(days: 13)) : o.daily.first.day;
    final DateTime endDay = o.startsAt.toLocal().isBefore(today) && !o.startsAt.toLocal().isBefore(lastSale) ? o.startsAt.toLocal() : (today.isAfter(lastSale) ? today : lastSale);
    final List<DayPoint> days = fillDays(o.daily, firstDay, endDay);
    final List<(DateTime, double)> series = _running
        ? runningTotal(days, revenue: _revenue)
        : <(DateTime, double)>[for (final DayPoint d in days) (d.day, _revenue ? d.revenueMinor / 100 : d.tickets.toDouble())];

    final List<Widget> tiles = <Widget>[
      StatTile(label: 'Tickets sold', value: '${o.totalSold}', caption: o.capacityTotal > 0 ? 'of ${o.capacityTotal} capacity' : 'no capacity set', icon: Icons.confirmation_number_outlined),
      StatTile(label: 'Revenue', value: pounds(o.revenueMinor), caption: o.sold == 0 ? null : 'average ${pounds(o.averageTicketMinor.round())} a ticket', icon: Icons.payments_outlined),
      if (o.capacityTotal > 0) StatTile(label: 'Remaining', value: '${o.remaining}', caption: 'places left', icon: Icons.event_seat_outlined),
      StatTile(label: 'Checked in', value: '${o.checkedIn}', caption: o.sold == 0 ? null : '${(o.checkedIn / o.sold * 100).round()}% of tickets', icon: Icons.how_to_reg_outlined),
      if (o.refunded > 0) StatTile(label: 'Refunded', value: '${o.refunded}', caption: 'tickets', icon: Icons.undo_outlined),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const double gap = FlcSpace.md;
        final double half = c.maxWidth > 980 ? (c.maxWidth - gap) / 2 : c.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(spacing: gap, runSpacing: gap, children: tiles),
            const SizedBox(height: gap),
            if (o.capacityTotal > 0)
              ChartCard(
                title: 'How full',
                subtitle: '${o.totalSold} of ${o.capacityTotal} places taken',
                child: _stackedBar(context, o, palette),
              ),
            if (o.capacityTotal > 0) const SizedBox(height: gap),
            ChartCard(
              title: 'Sales over time',
              subtitle: 'Day by day, in London time',
              trailing: Wrap(
                spacing: FlcSpace.sm,
                children: <Widget>[
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const <ButtonSegment<bool>>[ButtonSegment<bool>(value: false, label: Text('Tickets')), ButtonSegment<bool>(value: true, label: Text('Revenue'))],
                    selected: <bool>{_revenue},
                    onSelectionChanged: (Set<bool> s) => setState(() => _revenue = s.first),
                  ),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const <ButtonSegment<bool>>[ButtonSegment<bool>(value: true, label: Text('Total')), ButtonSegment<bool>(value: false, label: Text('Per day'))],
                    selected: <bool>{_running},
                    onSelectionChanged: (Set<bool> s) => setState(() => _running = s.first),
                  ),
                ],
              ),
              child: o.daily.isEmpty
                  ? const EmptyChart('No tickets sold yet.')
                  : AdminLineChart(points: series, format: (double v) => _revenue ? _money.format(v) : '${v.round()} ticket${v.round() == 1 ? '' : 's'}'),
            ),
            const SizedBox(height: gap),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                ChartCard(
                  width: half,
                  title: 'By ticket type',
                  subtitle: 'Share of tickets sold',
                  child: AdminDonut(slices: <(String, double)>[for (final TypeSales t in o.types) (t.name, t.sold.toDouble())], format: (double v) => '${v.round()}'),
                ),
                ChartCard(
                  width: half,
                  title: 'Ticket types',
                  subtitle: 'Sold against what was put on sale',
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < o.types.length; i++)
                        FillBar(
                          label: '${o.types[i].name} · ${o.types[i].priceMinor == 0 ? 'Free' : pounds(o.types[i].priceMinor)}',
                          value: o.types[i].sold,
                          of: o.types[i].quantity,
                          trailing: pounds(o.types[i].revenueMinor),
                          color: palette[i % palette.length],
                        ),
                      if (o.types.isEmpty) const EmptyChart('No ticket types.'),
                    ],
                  ),
                ),
              ],
            ),
            if (o.eventbriteSold > 0) ...<Widget>[
              const SizedBox(height: gap),
              Text('Includes ${o.eventbriteSold} sold on Eventbrite (counted in capacity, not in revenue here).', style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context))),
            ],
          ],
        );
      },
    );
  }

  Widget _stackedBar(BuildContext context, SalesOverview o, List<Color> palette) {
    final int cap = o.capacityTotal;
    final int app = o.sold.clamp(0, cap);
    final int eb = o.eventbriteSold.clamp(0, cap - app);
    final int left = cap - app - eb;
    Widget seg(int n, Color c) => n <= 0 ? const SizedBox.shrink() : Expanded(flex: n, child: Container(height: 18, color: c));
    Widget legend(String label, int n, Color c) => Padding(
          padding: const EdgeInsets.only(right: FlcSpace.md),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('$label · $n'),
          ]),
        );
    final Color empty = FlcColors.secondary(context).withValues(alpha: 0.2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(borderRadius: BorderRadius.circular(6), child: Row(children: <Widget>[seg(app, palette[0]), seg(eb, palette[1]), seg(left, empty)])),
        const SizedBox(height: FlcSpace.sm),
        Wrap(children: <Widget>[
          legend('Sold in the app', app, palette[0]),
          if (eb > 0) legend('Eventbrite', eb, palette[1]),
          legend('Left', left, empty),
        ]),
      ],
    );
  }
}
