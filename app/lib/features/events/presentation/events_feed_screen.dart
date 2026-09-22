import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/profile_provider.dart';
import '../events_providers.dart';
import 'event_card.dart';
import 'events_feed_controller.dart';

/// Which filter chip is selected. Fixed ones are plain ids; one chip per
/// category actually present in the upcoming events is `cat:<name>` — so the
/// row always matches what the club is really running, with no hard-coded
/// category list to fall out of date.
final StateProvider<String> _feedFilterProvider = StateProvider<String>((ref) => 'all');

const List<(String, String)> _fixedFilters = <(String, String)>[
  ('all', 'All'),
  ('week', 'This week'),
  ('offers', 'Offers'),
  ('members', 'Members only'),
  ('past', 'Past'),
];

/// Briefing §9.1. Chips: All / This week / Offers / Members only / Past,
/// then one per category in the current programme. On "All", events the
/// club has flagged FC Highlights are lifted into their own section at the
/// top. Everything reads chronologically: soonest-first for every upcoming
/// filter, most-recent-first for Past.
class EventsFeedScreen extends ConsumerWidget {
  const EventsFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsFeedControllerProvider);
    final filter = ref.watch(_feedFilterProvider);
    final sellingFast = ref.watch(sellingFastIdsProvider).valueOrNull ?? const <String>{};
    final isStaff = ref.watch(currentProfileProvider).valueOrNull?.isStaff ?? false;
    final bool showingPast = filter == 'past';

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
          eventsAsync.maybeWhen(
            data: (events) => _FilterChipsRow(
              options: <(String, String)>[..._fixedFilters, ..._categoryFilters(events)],
              selected: filter,
              onChanged: (id) => ref.read(_feedFilterProvider.notifier).state = id,
            ),
            orElse: () => const SizedBox(height: 48),
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

                      final bool grouped = filter == 'all';
                      final recommended = grouped ? filtered.where((e) => e.highlight == EventHighlight.fcRecommends).take(3).toList() : const <EventModel>[];
                      final recommendedIds = recommended.map((e) => e.id).toSet();
                      final rest = filtered.where((e) => !recommendedIds.contains(e.id)).toList();

                      Widget card(EventModel e) => EventCard(
                            event: e,
                            sellingFast: sellingFast.contains(e.id),
                            onTap: () => context.push('/events/${e.slug}'),
                          );

                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(sellingFastIdsProvider);
                          await ref.read(eventsFeedControllerProvider.notifier).refresh();
                        },
                        child: ListView(
                          children: <Widget>[
                            if (recommended.isNotEmpty) ...<Widget>[
                              const _SectionHeader(title: 'FC Highlights', icon: Icons.verified_outlined),
                              for (final e in recommended) card(e),
                              if (rest.isNotEmpty) const _SectionHeader(title: 'Coming up'),
                            ],
                            for (final e in rest) card(e),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FlcSpace.md, FlcSpace.md, FlcSpace.md, FlcSpace.xxs),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[Icon(icon, size: 18, color: FlcColors.brand), const SizedBox(width: FlcSpace.xs)],
          Text(title.toUpperCase(), style: FlcTextStyles.overline.copyWith(color: FlcColors.brand)),
        ],
      ),
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({required this.options, required this.selected, required this.onChanged});

  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
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
