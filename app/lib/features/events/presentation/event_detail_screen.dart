import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/membership_handle_visibility.dart';
import '../../checkout/domain/checkout_args.dart';
import '../events_providers.dart';

/// Briefing §9.2. Ships the informational blocks (date/venue/about/ticket
/// options) plus the sticky "Get tickets" bar now that M3 has something
/// for it to lead to. Still deferred: the Eventbrite fallback button
/// (needs eventbrite_sold to actually be non-zero to matter) and
/// sanitised-HTML rendering for description_html (flutter_widget_from_html_core).
class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  @override
  void dispose() {
    // Guarantees the handle comes back regardless of how this screen was
    // left (back gesture, programmatic pop, ...) — see
    // showMembershipHandleProvider's doc comment for why this matters.
    ref.read(showMembershipHandleProvider.notifier).state = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.slug));

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

/// Selection state for the ticket-type rows below — scoped to whichever
/// event detail screen is currently on top of the navigation stack.
/// autoDispose so a stale selection can never leak into the next event a
/// user opens.
final selectedTicketTypeIdProvider = StateProvider.autoDispose<String?>((ref) => null);
final ticketQuantityProvider = StateProvider.autoDispose<int>((ref) => 1);

class _EventDetailBody extends ConsumerWidget {
  const _EventDetailBody({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketTypesAsync = ref.watch(ticketTypesProvider(event.id));
    final selectedId = ref.watch(selectedTicketTypeIdProvider);
    final dateFormat = DateFormat('EEE d MMM yyyy, HH:mm'); // venue timezone, never device timezone — briefing §7.3

    TicketTypeModel? selected;
    for (final t in ticketTypesAsync.valueOrNull ?? const <TicketTypeModel>[]) {
      if (t.id == selectedId) {
        selected = t;
        break;
      }
    }

    return Scaffold(
      body: CustomScrollView(
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
            padding: EdgeInsets.fromLTRB(FlcSpace.md, FlcSpace.md, FlcSpace.md, selected != null ? 100 : FlcSpace.md),
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
                const Text('Tickets', style: FlcTextStyles.h3),
                const SizedBox(height: FlcSpace.sm),
                ticketTypesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: FlcSpace.md),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, stackTrace) => const Text("Couldn't load ticket options."),
                  data: (ticketTypes) => Column(
                    children: <Widget>[
                      for (final ticketType in ticketTypes)
                        _TicketTypeRow(
                          ticketType: ticketType,
                          selected: ticketType.id == selectedId,
                          onTap: !ticketType.onSale
                              ? null
                              : () {
                                  ref.read(selectedTicketTypeIdProvider.notifier).state = ticketType.id;
                                  ref.read(ticketQuantityProvider.notifier).state = 1;
                                  ref.read(showMembershipHandleProvider.notifier).state = false;
                                },
                        ),
                      if (ticketTypes.isEmpty) const Text('No tickets on sale yet.'),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: selected == null ? null : _BuyBar(event: event, ticketType: selected),
    );
  }
}

class _BuyBar extends ConsumerWidget {
  const _BuyBar({required this.event, required this.ticketType});

  final EventModel event;
  final TicketTypeModel ticketType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = ref.watch(ticketQuantityProvider);
    final totalMinor = ticketType.priceMinor * quantity;
    final totalDisplay = totalMinor == 0 ? 'Free' : '£${(totalMinor / 100).toStringAsFixed(2)}';

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: quantity > 1 ? () => ref.read(ticketQuantityProvider.notifier).state = quantity - 1 : null,
            ),
            Text('$quantity', style: FlcTextStyles.h3),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: quantity < ticketType.maxPerOrder
                  ? () => ref.read(ticketQuantityProvider.notifier).state = quantity + 1
                  : null,
            ),
            const SizedBox(width: FlcSpace.sm),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  ref.read(selectedTicketTypeIdProvider.notifier).state = null;
                  ref.read(showMembershipHandleProvider.notifier).state = true;
                  context.push(
                    '/events/${event.slug}/checkout',
                    extra: CheckoutArgs(
                      eventId: event.id,
                      eventTitle: event.title,
                      ticketTypeId: ticketType.id,
                      ticketTypeName: ticketType.name,
                      quantity: quantity,
                      pricePerUnitMinor: ticketType.priceMinor,
                      currency: ticketType.currency,
                    ),
                  );
                },
                child: Text('Get tickets — $totalDisplay'),
              ),
            ),
          ],
        ),
      ),
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
  const _TicketTypeRow({required this.ticketType, required this.selected, required this.onTap});

  final TicketTypeModel ticketType;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: FlcSpace.xs),
      shape: selected
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlcRadius.card), side: const BorderSide(color: FlcColors.brand, width: 2))
          : null,
      child: ListTile(
        title: Text(ticketType.name),
        subtitle: Text(!ticketType.onSale ? 'Not currently on sale' : ticketType.requiresProof ? 'Photo ID required at the door' : ''),
        trailing: Text(ticketType.priceDisplay, style: FlcTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        enabled: ticketType.onSale,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}
