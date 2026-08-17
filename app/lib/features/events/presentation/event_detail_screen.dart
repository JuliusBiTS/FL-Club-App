import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../events_providers.dart';

/// Briefing §9.2. Ships the informational blocks now (date/venue/about/
/// ticket options as read-only rows); the sticky "Get tickets" bottom bar,
/// Eventbrite fallback, filming-consent copy state, and sanitised-HTML
/// rendering (flutter_widget_from_html_core) are wired up together with
/// checkout in M3, since a buy button with nothing behind it is worse than
/// no buy button.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(slug));

    return Scaffold(
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Could not load this event.\n$error', textAlign: TextAlign.center)),
        data: (event) {
          if (event == null) {
            return const Center(child: Text('Event not found.'));
          }
          return _EventDetailBody(event: event);
        },
      ),
    );
  }
}

class _EventDetailBody extends ConsumerWidget {
  const _EventDetailBody({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketTypesAsync = ref.watch(ticketTypesProvider(event.id));
    final dateFormat = DateFormat('EEE d MMM yyyy, HH:mm'); // venue timezone, never device timezone — briefing §7.3

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(event.title, style: const TextStyle(fontSize: 16)),
            background: ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(FlcSpace.md),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              if (event.subtitle != null) ...<Widget>[
                Text(event.subtitle!, style: FlcTextStyles.body.copyWith(color: FlcColors.slate)),
                const SizedBox(height: FlcSpace.md),
              ],
              _InfoRow(icon: Icons.event_outlined, text: dateFormat.format(event.startsAt)),
              _InfoRow(icon: Icons.place_outlined, text: '${event.venueRoom ?? event.venueName}, ${event.venueAddress}'),
              if (event.isFilmed)
                const _InfoRow(
                  icon: Icons.videocam_outlined,
                  text: 'This event will be filmed. Footage may be used publicly and commercially.',
                ),
              const SizedBox(height: FlcSpace.lg),
              Text('Tickets', style: FlcTextStyles.h3),
              const SizedBox(height: FlcSpace.sm),
              ticketTypesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: FlcSpace.md),
                  child: LinearProgressIndicator(),
                ),
                error: (error, stackTrace) => const Text("Couldn't load ticket options."),
                data: (ticketTypes) => Column(
                  children: <Widget>[
                    for (final ticketType in ticketTypes) _TicketTypeRow(ticketType: ticketType),
                    if (ticketTypes.isEmpty) const Text('No tickets on sale yet.'),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlcSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: FlcColors.slate),
          const SizedBox(width: FlcSpace.xs),
          Expanded(child: Text(text, style: FlcTextStyles.body)),
        ],
      ),
    );
  }
}

class _TicketTypeRow extends StatelessWidget {
  const _TicketTypeRow({required this.ticketType});

  final TicketTypeModel ticketType;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: FlcSpace.xs),
      child: ListTile(
        title: Text(ticketType.name),
        subtitle: ticketType.requiresProof ? const Text('Photo ID required at the door') : null,
        trailing: Text(ticketType.priceDisplay, style: FlcTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        enabled: ticketType.onSale,
      ),
    );
  }
}
