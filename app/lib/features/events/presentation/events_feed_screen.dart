import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'event_card.dart';
import 'events_feed_controller.dart';

enum _FeedFilter { all, thisWeek, membersOnly, free }

final StateProvider<_FeedFilter> _feedFilterProvider = StateProvider<_FeedFilter>((ref) => _FeedFilter.all);

/// Briefing §9.1. Category-specific chips (Panels/Screenings/Book nights)
/// need `category` values the club hasn't finalised yet, so this ships
/// with the filters that don't depend on that vocabulary; the rest are a
/// straightforward extension once it's confirmed.
class EventsFeedScreen extends ConsumerWidget {
  const EventsFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsFeedControllerProvider);
    final filter = ref.watch(_feedFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () {
              // TODO(M1 polish): full-text search across title/summary/speakers/tags.
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _FilterChipsRow(selected: filter, onChanged: (f) => ref.read(_feedFilterProvider.notifier).state = f),
          Expanded(
            child: eventsAsync.when(
              loading: () => const _ShimmerList(),
              error: (error, stackTrace) => _ErrorState(onRetry: () => ref.read(eventsFeedControllerProvider.notifier).refresh()),
              data: (events) {
                final filtered = _applyFilter(events, filter);
                if (filtered.isEmpty) return const _EmptyState();
                return RefreshIndicator(
                  onRefresh: () => ref.read(eventsFeedControllerProvider.notifier).refresh(),
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final event = filtered[index];
                      return EventCard(event: event, onTap: () => context.push('/events/${event.slug}'));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<EventModel> _applyFilter(List<EventModel> events, _FeedFilter filter) {
    switch (filter) {
      case _FeedFilter.all:
        return events;
      case _FeedFilter.thisWeek:
        final now = DateTime.now();
        final weekFromNow = now.add(const Duration(days: 7));
        return events.where((e) => e.startsAt.isBefore(weekFromNow)).toList();
      case _FeedFilter.membersOnly:
        return events.where((e) => e.membersOnly).toList();
      case _FeedFilter.free:
        return events; // needs ticket_types pricing — resolved once the feed carries a min price per event (M3)
    }
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({required this.selected, required this.onChanged});

  final _FeedFilter selected;
  final ValueChanged<_FeedFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <(_FeedFilter, String)>[
      (_FeedFilter.all, 'All'),
      (_FeedFilter.thisWeek, 'This week'),
      (_FeedFilter.membersOnly, 'Members only'),
    ];

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
        children: <Widget>[
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: FlcSpace.xs),
              child: ChoiceChip(
                label: Text(option.$2),
                selected: selected == option.$1,
                onSelected: (_) => onChanged(option.$1),
              ),
            ),
        ],
      ),
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
  const _EmptyState();

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
              'No events scheduled right now — new events are usually announced a few weeks ahead',
              textAlign: TextAlign.center,
              style: FlcTextStyles.body,
            ),
            const SizedBox(height: FlcSpace.md),
            FilledButton(
              onPressed: () {
                // TODO(M9): enable push and subscribe to "new events" notifications.
              },
              child: const Text('Notify me'),
            ),
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
