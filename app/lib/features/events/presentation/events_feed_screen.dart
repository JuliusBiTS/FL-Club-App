import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/profile_provider.dart';
import '../events_providers.dart';
import 'event_card.dart';
import 'events_feed_controller.dart';

/// Which filter is selected, independent of Upcoming/Past (see
/// _showingPastProvider) — a single value, not a set, so "Offers" and
/// "Members only" are still mutually exclusive with each other and with a
/// category. Feedback: too many chips visible at once looked messy, so
/// these now live behind a single filter button instead of a scroll row.
final StateProvider<String> _feedFilterProvider = StateProvider<String>((ref) => 'all');

/// Upcoming vs Past is a more fundamental split than any of the filters
/// above (different query, different sort direction, no FC Highlights
/// grouping in Past) so it gets its own toggle rather than being one more
/// option buried in the filter sheet.
final StateProvider<bool> _showingPastProvider = StateProvider<bool>((ref) => false);

const List<(String, String)> _fixedFilters = <(String, String)>[
  ('all', 'All'),
  ('week', 'In the next 7 days'),
  ('offers', 'Offers'),
  ('members', 'Members only'),
];

/// Briefing §9.1. Upcoming/Past toggle, one filter button (rather than a
/// row of chips), and — feedback — always strictly chronological:
/// soonest-first for Upcoming, most-recent-first for Past. FC Highlights
/// still shows as a ribbon on its card, it just no longer jumps the event
/// out of date order into its own section.
class EventsFeedScreen extends ConsumerWidget {
  const EventsFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsFeedControllerProvider);
    final filter = ref.watch(_feedFilterProvider);
    final showingPast = ref.watch(_showingPastProvider);
    final sellingFast = ref.watch(sellingFastIdsProvider).valueOrNull ?? const <String>{};
    final isStaff = ref.watch(currentProfileProvider).valueOrNull?.isStaff ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: <Widget>[
          if (isStaff)
            IconButton(
              icon: const Icon(Icons.edit_calendar_outlined),
              tooltip: 'Manage events',
              onPressed: () => context.push('/manage/events'),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(FlcSpace.md, FlcSpace.sm, FlcSpace.md, FlcSpace.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment(value: false, label: Text('Upcoming')),
                      ButtonSegment(value: true, label: Text('Past')),
                    ],
                    selected: <bool>{showingPast},
                    onSelectionChanged: (selection) => ref.read(_showingPastProvider.notifier).state = selection.first,
                  ),
                ),
                if (!showingPast) ...<Widget>[
                  const SizedBox(width: FlcSpace.sm),
                  eventsAsync.maybeWhen(
                    data: (events) => _FilterButton(
                      selected: filter,
                      categories: _categoryFilters(events),
                      onChanged: (id) => ref.read(_feedFilterProvider.notifier).state = id,
                    ),
                    orElse: () => const SizedBox(width: 48),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: showingPast
                ? _PastEventsList(onTap: (slug) => context.push('/events/$slug'))
                : eventsAsync.when(
                    loading: () => const _ShimmerList(),
                    error: (error, stackTrace) => _ErrorState(onRetry: () => ref.read(eventsFeedControllerProvider.notifier).refresh()),
                    data: (events) {
                      final filtered = _applyFilter(events, filter);
                      if (filtered.isEmpty) return _EmptyState(filtered: events.isNotEmpty);

                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(sellingFastIdsProvider);
                          await ref.read(eventsFeedControllerProvider.notifier).refresh();
                        },
                        child: ListView(
                          children: <Widget>[
                            // Already ascending by starts_at (see
                            // EventsRemoteDataSource.fetchUpcomingPublished)
                            // — rendered in that order with nothing lifted
                            // out of it, so soonest is always first.
                            for (final e in filtered)
                              EventCard(
                                event: e,
                                sellingFast: sellingFast.contains(e.id),
                                onTap: () => context.push('/events/${e.slug}'),
                              ),
                            const SizedBox(height: FlcSpace.xl),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _categoryFilters(List<EventModel> events) {
    final seen = <String>[];
    for (final e in events) {
      final c = e.category;
      if (c != null && c.isNotEmpty && !seen.contains(c)) seen.add(c);
    }
    return <(String, String)>[for (final c in seen.take(8)) ('cat:$c', c)];
  }

  List<EventModel> _applyFilter(List<EventModel> events, String filter) {
    if (filter.startsWith('cat:')) {
      final name = filter.substring(4);
      return events.where((e) => e.category == name).toList();
    }
    switch (filter) {
      case 'week':
        final weekFromNow = DateTime.now().add(const Duration(days: 7));
        return events.where((e) => e.startsAt.isBefore(weekFromNow)).toList();
      case 'offers':
        return events.where((e) => e.highlight == EventHighlight.specialOffer || e.perks.isNotEmpty).toList();
      case 'members':
        return events.where((e) => e.membersOnly).toList();
      default:
        return events;
    }
  }
}

/// One button in place of the old scrolling chip row. Shows a dot when a
/// non-default filter is active, and opens a bottom sheet grouped into
/// "When it's on" / "Category" rather than one long flat list.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.selected, required this.categories, required this.onChanged});

  final String selected;
  final List<(String, String)> categories;
  final ValueChanged<String> onChanged;

  String _label(String id) {
    for (final f in _fixedFilters) {
      if (f.$1 == id) return f.$2;
    }
    for (final c in categories) {
      if (c.$1 == id) return c.$2;
    }
    return 'Filter';
  }

  @override
  Widget build(BuildContext context) {
    final bool active = selected != 'all';
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: () => _openSheet(context),
          icon: const Icon(Icons.tune, size: 18),
          label: Text(active ? _label(selected) : 'Filter', overflow: TextOverflow.ellipsis),
        ),
        if (active)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: FlcColors.brand, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: FlcSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final f in _fixedFilters) _SheetRow(id: f.$1, label: f.$2, selected: selected, onChanged: onChanged),
              if (categories.isNotEmpty) ...<Widget>[
                const Divider(height: FlcSpace.md),
                Padding(
                  padding: const EdgeInsets.fromLTRB(FlcSpace.md, 0, FlcSpace.md, FlcSpace.xxs),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('CATEGORY', style: FlcTextStyles.overline.copyWith(color: FlcColors.slate)),
                  ),
                ),
                for (final c in categories) _SheetRow(id: c.$1, label: c.$2, selected: selected, onChanged: onChanged),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.id, required this.label, required this.selected, required this.onChanged});

  final String id;
  final String label;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool isSelected = id == selected;
    return ListTile(
      title: Text(label),
      trailing: isSelected ? Icon(Icons.check, color: FlcColors.accent(context)) : null,
      onTap: () {
        onChanged(id);
        Navigator.of(context).pop();
      },
    );
  }
}

class _PastEventsList extends ConsumerWidget {
  const _PastEventsList({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pastAsync = ref.watch(pastEventsProvider);
    return pastAsync.when(
      loading: () => const _ShimmerList(),
      error: (error, stackTrace) => _ErrorState(onRetry: () => ref.invalidate(pastEventsProvider)),
      data: (events) {
        if (events.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(FlcSpace.lg),
              child: Text('No past events yet.', style: FlcTextStyles.body, textAlign: TextAlign.center),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(pastEventsProvider),
          child: ListView(
            children: <Widget>[
              for (final e in events) EventCard(event: e, onTap: () => onTap(e.slug)),
              const SizedBox(height: FlcSpace.xl),
            ],
          ),
        );
      },
    );
  }
}

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
        height: 220,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(FlcRadius.card),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});

  /// True when there ARE events, just none matching the chosen chip.
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.event_busy_outlined, size: 40, color: FlcColors.slate),
            const SizedBox(height: FlcSpace.sm),
            Text(
              filtered
                  ? 'Nothing matches that filter right now.'
                  : 'No events scheduled right now — new events are usually announced a few weeks ahead',
              textAlign: TextAlign.center,
              style: FlcTextStyles.body,
            ),
            if (!filtered) ...<Widget>[
              const SizedBox(height: FlcSpace.md),
              FilledButton(
                onPressed: () => context.push('/you/notifications'),
                child: const Text('Notify me'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text("Couldn't load events."),
          const SizedBox(height: FlcSpace.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
