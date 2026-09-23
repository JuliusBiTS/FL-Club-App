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

/// Feedback: "add a sorting option ... that just lets me flip the date
/// sort". False = the existing default (soonest-first for Upcoming,
/// most-recent-first for Past); true reverses whichever list is showing.
/// Shared across both tabs rather than one toggle each — simplest reading
/// of "flip it" for a single button.
final StateProvider<bool> _reverseSortProvider = StateProvider<bool>((ref) => false);

const List<(String, String)> _fixedFilters = <(String, String)>[
  ('all', 'All'),
  ('week', 'In the next 7 days'),
  ('offers', 'Offers'),
  ('members', 'Members only'),
];

/// Briefing §9.1. Upcoming/Past toggle, one filter button (rather than a
/// row of chips). On "All", FC Highlights events are lifted into their own
/// section at the top (feedback: bring this back); every other filter, and
/// the section itself, and "Coming up" below it, are each strictly
/// chronological — soonest-first for Upcoming, most-recent-first for Past.
class EventsFeedScreen extends ConsumerWidget {
  const EventsFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsFeedControllerProvider);
    final filter = ref.watch(_feedFilterProvider);
    final showingPast = ref.watch(_showingPastProvider);
    final reverseSort = ref.watch(_reverseSortProvider);
    final sellingFast = ref.watch(sellingFastIdsProvider).valueOrNull ?? const <String>{};
    final soldOut = ref.watch(soldOutIdsProvider).valueOrNull ?? const <String>{};
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
                const SizedBox(width: FlcSpace.sm),
                _FilterButton(
                  selected: filter,
                  categories: eventsAsync.maybeWhen(data: _categoryFilters, orElse: () => const <(String, String)>[]),
                  onChanged: (id) => ref.read(_feedFilterProvider.notifier).state = id,
                  showFilter: !showingPast,
                  reverse: reverseSort,
                  onFlip: () => ref.read(_reverseSortProvider.notifier).state = !reverseSort,
                ),
              ],
            ),
          ),
          Expanded(
            child: showingPast
                ? _PastEventsList(reverse: reverseSort, onTap: (slug) => context.push('/events/$slug'))
                : eventsAsync.when(
                    loading: () => const _ShimmerList(),
                    error: (error, stackTrace) => _ErrorState(onRetry: () => ref.read(eventsFeedControllerProvider.notifier).refresh()),
                    data: (events) {
                      final matching = _applyFilter(events, filter);
                      if (matching.isEmpty) return _EmptyState(filtered: events.isNotEmpty);
                      final filtered = reverseSort ? matching.reversed.toList() : matching;

                      // Events already arrive ascending by starts_at (see
                      // EventsRemoteDataSource.fetchUpcomingPublished), so
                      // both of these stay chronological among themselves —
                      // only the recommended ones move, as a whole group,
                      // ahead of everything else.
                      final bool grouped = filter == 'all';
                      final recommended = grouped ? filtered.where((e) => e.highlight == EventHighlight.fcRecommends).take(3).toList() : const <EventModel>[];
                      final recommendedIds = recommended.map((e) => e.id).toSet();
                      final rest = filtered.where((e) => !recommendedIds.contains(e.id)).toList();

                      Widget card(EventModel e) => EventCard(
                            event: e,
                            sellingFast: sellingFast.contains(e.id),
                            soldOut: soldOut.contains(e.id),
                            onTap: () => context.push('/events/${e.slug}'),
                          );

                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(sellingFastIdsProvider);
                          ref.invalidate(soldOutIdsProvider);
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

/// One button in place of the old scrolling chip row. Shows a dot when a
/// non-default filter is active, and opens a bottom sheet grouped into
/// "When it's on" / "Category" rather than one long flat list.
/// One pill holding both controls: "Filter" (opens the sheet; hidden on the
/// Past tab, which has nothing to filter) and the date-order arrow. Feedback:
/// the loose arrow beside the toggle looked bad and shoved the text around.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.selected,
    required this.categories,
    required this.onChanged,
    required this.showFilter,
    required this.reverse,
    required this.onFlip,
  });

  final String selected;
  final List<(String, String)> categories;
  final ValueChanged<String> onChanged;
  final bool showFilter;
  final bool reverse;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final bool active = showFilter && selected != 'all';
    final Color color = FlcColors.accent(context);
    final Color border = Theme.of(context).colorScheme.outline;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Material(
          color: Colors.transparent,
          shape: StadiumBorder(side: BorderSide(color: border)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (showFilter) ...<Widget>[
                  // Always just "Filter" — a category name here would grow the
                  // pill and squeeze the Upcoming/Past toggle. The dot is the
                  // "something's filtered" signal instead.
                  InkWell(
                    onTap: () => _openSheet(context),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.tune, size: 18, color: color),
                          const SizedBox(width: 6),
                          Text('Filter', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, indent: 8, endIndent: 8, color: border),
                ],
                Tooltip(
                  message: reverse ? 'Latest first — tap to flip' : 'Earliest first — tap to flip',
                  child: InkWell(
                    onTap: onFlip,
                    child: SizedBox(
                      width: 44,
                      height: 40,
                      child: Icon(reverse ? Icons.arrow_upward : Icons.arrow_downward, size: 20, color: color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (active)
          Positioned(
            left: 4,
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
                    child: Text('CATEGORY', style: FlcTextStyles.overline.copyWith(color: FlcColors.secondary(context))),
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
          if (icon != null) ...<Widget>[Icon(icon, size: 18, color: FlcColors.accent(context)), const SizedBox(width: FlcSpace.xs)],
          Text(title.toUpperCase(), style: FlcTextStyles.overline.copyWith(color: FlcColors.accent(context))),
        ],
      ),
    );
  }
}

class _PastEventsList extends ConsumerWidget {
  const _PastEventsList({required this.onTap, this.reverse = false});

  final ValueChanged<String> onTap;
  final bool reverse;

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
              for (final e in (reverse ? events.reversed : events)) EventCard(event: e, onTap: () => onTap(e.slug)),
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
            Icon(Icons.event_busy_outlined, size: 40, color: FlcColors.secondary(context)),
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
