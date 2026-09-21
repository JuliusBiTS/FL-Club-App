import 'package:flutter/material.dart';

import '../models/event.dart';
import '../theme/flc_colors.dart';
import '../theme/flc_spacing.dart';
import '../theme/flc_typography.dart';
import '../util/london_time.dart';
import '../widgets/event_badges.dart';
import '../widgets/event_hero_fallback.dart';
import 'event_admin_repository.dart';
import 'event_editor_screen.dart';
import 'event_preview.dart';

enum _Filter { upcoming, live, drafts, scheduled, past, closed }

extension on _Filter {
  String get label => switch (this) {
        _Filter.upcoming => 'Upcoming',
        _Filter.live => 'Live',
        _Filter.drafts => 'Drafts',
        _Filter.scheduled => 'Scheduled',
        _Filter.past => 'Past',
        _Filter.closed => 'Cancelled & archived',
      };
}

/// Every event — drafts, scheduled, live, past — with search, filters and a
/// "New event" button. Shared by the admin console (embedded in its shell)
/// and the app's staff area (its own screen).
class EventsManagerScreen extends StatefulWidget {
  const EventsManagerScreen({required this.repository, required this.isAdmin, this.embedded = false, super.key});

  final EventAdminRepository repository;
  final bool isAdmin;

  /// True inside the admin console's shell (no app bar of its own).
  final bool embedded;

  @override
  State<EventsManagerScreen> createState() => _EventsManagerScreenState();
}

class _EventsManagerScreenState extends State<EventsManagerScreen> {
  late Future<(List<EventModel>, Set<String>)> _future = _load();
  _Filter _filter = _Filter.upcoming;
  String _search = '';

  Future<(List<EventModel>, Set<String>)> _load() async {
    final List<EventModel> events = await widget.repository.listEvents();
    final Set<String> fast = await widget.repository.sellingFastIds();
    return (events, fast);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _open({String? id}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) => EventEditorScreen(repository: widget.repository, isAdmin: widget.isAdmin, eventId: id),
      ),
    );
    if (mounted) _reload();
  }

  bool _matches(EventModel e) {
    final DateTime now = DateTime.now().toUtc();
    final bool isPast = e.startsAt.toUtc().isBefore(now.subtract(const Duration(hours: 6)));
    final bool closed = e.status == 'cancelled' || e.status == 'archived';
    switch (_filter) {
      case _Filter.upcoming:
        return !closed && !isPast;
      case _Filter.live:
        return e.status == 'published' && !isPast;
      case _Filter.drafts:
        return e.status == 'draft' && e.publishAt == null;
      case _Filter.scheduled:
        return e.isScheduled;
      case _Filter.past:
        return !closed && isPast;
      case _Filter.closed:
        return closed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(FlcSpace.xl, FlcSpace.xl, FlcSpace.xl, FlcSpace.sm),
            child: Row(
              children: <Widget>[
                Text('Events', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _reload),
                const SizedBox(width: FlcSpace.xs),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.add),
                  label: const Text('New event'),
                  onPressed: () => _open(),
                ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.embedded ? FlcSpace.xl : FlcSpace.md, vertical: FlcSpace.xs),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search title, category, speaker…', isDense: true),
            onChanged: (String v) => setState(() => _search = v.trim().toLowerCase()),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: widget.embedded ? FlcSpace.xl : FlcSpace.md, vertical: FlcSpace.xs),
            children: <Widget>[
              for (final _Filter f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: FlcSpace.xs),
                  child: ChoiceChip(label: Text(f.label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<(List<EventModel>, Set<String>)>(
            future: _future,
            builder: (BuildContext context, AsyncSnapshot<(List<EventModel>, Set<String>)> snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('Couldn\'t load events.\n${EventAdminRepository.describeError(snap.error!)}', textAlign: TextAlign.center),
                      const SizedBox(height: FlcSpace.sm),
                      OutlinedButton(onPressed: _reload, child: const Text('Try again')),
                    ],
                  ),
                );
              }
              final List<EventModel> all = snap.data!.$1;
              final Set<String> fast = snap.data!.$2;

              List<EventModel> shown = all.where(_matches).where((EventModel e) {
                if (_search.isEmpty) return true;
                return e.title.toLowerCase().contains(_search) ||
                    (e.category ?? '').toLowerCase().contains(_search) ||
                    e.tags.any((String t) => t.toLowerCase().contains(_search)) ||
                    e.speakers.any((EventSpeaker s) => s.name.toLowerCase().contains(_search));
              }).toList();
              // Upcoming/live/drafts read soonest-first; past & closed newest-first.
              if (_filter != _Filter.past && _filter != _Filter.closed) {
                shown = shown.reversed.toList();
              }

              if (shown.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(FlcSpace.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.event_busy_outlined, size: 40, color: FlcColors.slate),
                        const SizedBox(height: FlcSpace.sm),
                        Text(all.isEmpty ? 'No events yet — create the first one.' : 'No events match.', style: FlcTextStyles.body),
                      ],
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _future;
                },
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(widget.embedded ? FlcSpace.xl : FlcSpace.md, FlcSpace.xs, widget.embedded ? FlcSpace.xl : FlcSpace.md, 96),
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int i) => _EventRow(event: shown[i], sellingFast: fast.contains(shown[i].id), onTap: () => _open(id: shown[i].id)),
                ),
              );
            },
          ),
        ),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage events'),
        actions: <Widget>[IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _reload)],
      ),
      body: content,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: FlcColors.brand,
        foregroundColor: Colors.white,
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.sellingFast, required this.onTap});

  final EventModel event;
  final bool sellingFast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String when = LondonTime.format(event.startsAt, pattern: 'EEE d MMM yyyy, HH:mm');
    final String where = event.venueRoom ?? event.venueName;

    return Card(
      margin: const EdgeInsets.only(bottom: FlcSpace.xs),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FlcSpace.sm),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(FlcRadius.input),
                child: SizedBox(
                  width: 88,
                  height: 62,
                  child: event.heroImagePath == null
                      ? EventHeroFallback(category: event.category, showLabel: false)
                      : Image.network(event.heroImagePath!, fit: BoxFit.cover, errorBuilder: (BuildContext c, Object e, StackTrace? s) => const ColoredBox(color: FlcColors.line)),
                ),
              ),
              const SizedBox(width: FlcSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlcTextStyles.h3.copyWith(fontSize: 16, height: 1.25)),
                    const SizedBox(height: 2),
                    Text(
                      '$when · $where${event.category == null ? '' : ' · ${event.category}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate),
                    ),
                    if (event.isPromoted || sellingFast) ...<Widget>[
                      const SizedBox(height: FlcSpace.xs),
                      EventBadges(highlight: event.highlight, perks: event.perks, sellingFast: sellingFast, dense: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: FlcSpace.xs),
              EventStatusChip(status: event.status, scheduled: event.isScheduled),
              const Icon(Icons.chevron_right, color: FlcColors.slate),
            ],
          ),
        ),
      ),
    );
  }
}
