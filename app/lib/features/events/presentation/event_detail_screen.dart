import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/profile_provider.dart';
import '../../../core/ui/membership_handle_visibility.dart';
import '../../checkout/domain/checkout_args.dart';
import '../../events_admin/events_admin_providers.dart';
import '../events_providers.dart';
import 'events_feed_controller.dart';

/// Briefing §9.2. Everything the club can enter in the event editor shows up
/// here: picture, ribbons, date/venue in London time, description, speakers,
/// links, accessibility notes and the ticket options, with the sticky
/// "Get tickets" bar once a ticket type is chosen. Still deferred: the
/// Eventbrite fallback button (needs eventbrite_sold to matter).
class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  // `ref` may not be used once the element is unmounting (Riverpod throws
  // "Cannot use ref after the widget was disposed" — which also meant the
  // handle below was never restored), so hold on to the container instead.
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    // Guarantees the membership-card handle comes back regardless of how this
    // screen was left (back gesture, programmatic pop, ...) — see
    // showMembershipHandleProvider's doc comment for why this matters.
    // Deferred a tick: providers must not be modified in the middle of the
    // widget tree being torn down.
    final container = _container;
    Future<void>.microtask(() {
      try {
        container.read(showMembershipHandleProvider.notifier).state = true;
      } catch (_) {
        // The whole app is shutting down; nothing left to restore.
      }
    });
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

Future<bool> _openWebLink(String url) async {
  final uri = Uri.tryParse(url.trim());
  // Only ever open web links — never an arbitrary scheme from event data.
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

IconData _linkIcon(String kind) => switch (kind) {
      EventLinkKind.book => Icons.menu_book_outlined,
      EventLinkKind.film => Icons.movie_outlined,
      EventLinkKind.article => Icons.article_outlined,
      EventLinkKind.video => Icons.play_circle_outline,
      EventLinkKind.donate => Icons.favorite_border,
      _ => Icons.open_in_new,
    };

class _EventDetailBody extends ConsumerWidget {
  const _EventDetailBody({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketTypesAsync = ref.watch(ticketTypesProvider(event.id));
    final selectedId = ref.watch(selectedTicketTypeIdProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isStaff = profile?.isStaff ?? false;
    final sellingFast = ref.watch(sellingFastIdsProvider).valueOrNull?.contains(event.id) ?? false;
    final bookable = event.status == 'published';

    TicketTypeModel? selected;
    for (final t in ticketTypesAsync.valueOrNull ?? const <TicketTypeModel>[]) {
      if (t.id == selectedId) {
        selected = t;
        break;
      }
    }

    final startsAt = event.startsAt;
    final endsAt = event.endsAt;
    final doorsAt = event.doorsAt;
    String hm(DateTime t) => LondonTime.format(t, pattern: 'HH:mm');
    final timeLine = <String>[
      if (doorsAt != null) 'Doors ${hm(doorsAt)}',
      'Starts ${hm(startsAt)}${endsAt == null ? '' : ' – ${hm(endsAt)}'}',
    ].join(' · ');

    // "Watch live" only appears around the event itself, so a stream link
    // isn't on show for weeks beforehand.
    final now = DateTime.now().toUtc();
    final watchWindowOpen = event.isOnline &&
        (event.livestreamUrl ?? '').isNotEmpty &&
        now.isAfter(startsAt.toUtc().subtract(const Duration(minutes: 15))) &&
        now.isBefore((endsAt ?? startsAt.add(const Duration(hours: 3))).toUtc());

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            actions: <Widget>[
              if (isStaff)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit this event',
                  onPressed: () => _openEditor(context, ref, isAdmin: profile?.isAdmin ?? false),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(event.title, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
              background: _Hero(event: event),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(FlcSpace.md, FlcSpace.md, FlcSpace.md, bookable && selected != null ? 100 : FlcSpace.xl),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                if (!bookable) _StatusBanner(status: event.status),
                if (event.isPromoted || sellingFast) ...<Widget>[
                  EventBadges(highlight: event.highlight, perks: event.perks, sellingFast: sellingFast),
                  const SizedBox(height: FlcSpace.md),
                ],
                if (event.subtitle != null && event.subtitle!.isNotEmpty) ...<Widget>[
                  Text(event.subtitle!, style: FlcTextStyles.body.copyWith(color: FlcColors.slate)),
                  const SizedBox(height: FlcSpace.md),
                ],
                _InfoRow(icon: Icons.event_outlined, text: LondonTime.format(startsAt, pattern: 'EEEE d MMMM yyyy')),
                _InfoRow(icon: Icons.schedule_outlined, text: timeLine),
                _InfoRow(
                  icon: Icons.place_outlined,
                  text: '${event.venueRoom == null || event.venueRoom!.isEmpty ? event.venueName : '${event.venueRoom}, ${event.venueName}'}\n${event.venueAddress}',
                ),
                if (event.isOnline) const _InfoRow(icon: Icons.live_tv_outlined, text: 'Also streamed online'),
                if (watchWindowOpen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FlcSpace.sm),
                    child: FilledButton.icon(
                      onPressed: () => _openWebLink(event.livestreamUrl!),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Watch live'),
                    ),
                  ),
                if (event.membersOnly)
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    text: (profile?.isActiveMember ?? false)
                        ? 'Members only — you\'re a member, so you can book.'
                        : 'Members only — booking needs an active membership.',
                  ),
                if (event.loyaltyEligible) const _InfoRow(icon: Icons.loyalty_outlined, text: 'Paid tickets earn a loyalty point.'),
                if (event.isFilmed)
                  const _InfoRow(
                    icon: Icons.videocam_outlined,
                    text: 'This event will be filmed. Footage may be used publicly and commercially.',
                  ),
                if (event.accessibilityNotes != null && event.accessibilityNotes!.trim().isNotEmpty)
                  _InfoRow(icon: Icons.accessible_outlined, text: event.accessibilityNotes!.trim()),
                if ((event.descriptionHtml ?? '').trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.md),
                  const Text('About', style: FlcTextStyles.h3),
                  const SizedBox(height: FlcSpace.sm),
                  HtmlWidget(
                    event.descriptionHtml!,
                    textStyle: FlcTextStyles.body,
                    onTapUrl: _openWebLink,
                  ),
                ] else if ((event.summary ?? '').trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.md),
                  Text(event.summary!, style: FlcTextStyles.body),
                ],
                if (event.speakers.isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.lg),
                  const Text('Speakers', style: FlcTextStyles.h3),
                  const SizedBox(height: FlcSpace.sm),
                  for (final s in event.speakers) _SpeakerTile(speaker: s),
                ],
                if (event.links.isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.md),
                  Wrap(
                    spacing: FlcSpace.xs,
                    runSpacing: FlcSpace.xs,
                    children: <Widget>[
                      for (final l in event.links)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: () => _openWebLink(l.url),
                          icon: Icon(_linkIcon(l.kind), size: 18),
                          label: Text(l.label),
                        ),
                    ],
                  ),
                ],
                if (event.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: FlcSpace.md),
                  Wrap(
                    spacing: FlcSpace.xs,
                    runSpacing: FlcSpace.xxs,
                    children: <Widget>[for (final t in event.tags) Chip(label: Text(t), visualDensity: VisualDensity.compact)],
                  ),
                ],
                if (bookable) ...<Widget>[
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
                ],
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: !bookable || selected == null ? null : _BuyBar(event: event, ticketType: selected),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, {required bool isAdmin}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventEditorScreen(repository: ref.read(eventAdminRepositoryProvider), isAdmin: isAdmin, eventId: event.id),
      ),
    );
    // Pull the fresh copy straight past the local cache, then redraw.
    await ref.read(eventsRepositoryProvider).getEventDetail(event.slug, forceRefresh: true);
    ref.invalidate(eventDetailProvider(event.slug));
    await ref.read(eventsFeedControllerProvider.notifier).refresh();
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (event.heroImagePath == null)
          EventHeroFallback(category: event.category, showLabel: false)
        else
          CachedNetworkImage(
            imageUrl: event.heroImagePath!,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => EventHeroFallback(category: event.category, showLabel: false),
          ),
        // Keeps the white title readable over any photo.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x33000000), Colors.transparent, Color(0x99000000)],
              stops: <double>[0, 0.4, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (String text, Color color) = switch (status) {
      'cancelled' => ('This event has been cancelled.', FlcColors.error),
      'postponed' => ('This event has been postponed. We\'ll confirm a new date soon.', FlcColors.warning),
      'draft' => ('Draft — only staff can see this.', FlcColors.slate),
      _ => ('This event is no longer on sale.', FlcColors.slate),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: FlcSpace.md),
      padding: const EdgeInsets.all(FlcSpace.sm),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(FlcRadius.input)),
      child: Text(text, style: FlcTextStyles.bodySmall.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _SpeakerTile extends StatelessWidget {
  const _SpeakerTile({required this.speaker});

  final EventSpeaker speaker;

  @override
  Widget build(BuildContext context) {
    final initials = speaker.name.trim().isEmpty
        ? '?'
        : speaker.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return Padding(
      padding: const EdgeInsets.only(bottom: FlcSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 26,
            backgroundColor: FlcColors.brand.withValues(alpha: 0.10),
            backgroundImage: speaker.photoUrl == null ? null : CachedNetworkImageProvider(speaker.photoUrl!),
            child: speaker.photoUrl == null ? Text(initials, style: FlcTextStyles.h3.copyWith(color: FlcColors.brand)) : null,
          ),
          const SizedBox(width: FlcSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(speaker.name, style: FlcTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                if (speaker.role != null && speaker.role!.isNotEmpty)
                  Text(speaker.role!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.brand)),
                if (speaker.bio != null && speaker.bio!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(speaker.bio!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.slate)),
                ],
              ],
            ),
          ),
        ],
      ),
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
        subtitle: !ticketType.onSale ? const Text('Not currently on sale') : ticketType.requiresProof ? const Text('Photo ID required at the door') : null,
        trailing: Text(ticketType.priceDisplay, style: FlcTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
        enabled: ticketType.onSale,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}
