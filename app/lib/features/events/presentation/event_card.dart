import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

/// Briefing §9.1. Full member-price surfacing (struck-through standard
/// price, live ticket-type-aware pricing) needs the event's ticket types,
/// which the feed doesn't fetch per-card for cost/latency reasons — that
/// richer version lands later. Today it shows the picture (or the brand
/// fallback), date/venue in London time, and the promotional ribbons the
/// club has chosen — FC Highlights / Special offer / perks — plus "Selling
/// fast", which is derived from sales rather than set by hand.
class EventCard extends StatelessWidget {
  const EventCard({required this.event, required this.onTap, this.sellingFast = false, this.soldOut = false, super.key});

  final EventModel event;
  final VoidCallback onTap;
  final bool sellingFast;
  final bool soldOut;

  @override
  Widget build(BuildContext context) {
    // Venue time, never device time (briefing §6/§7.3).
    final String when = LondonTime.format(event.startsAt, pattern: 'EEE d MMM, HH:mm');

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: FlcSpace.md, vertical: FlcSpace.xs),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: event.heroImagePath == null
                  ? EventHeroFallback(category: event.category)
                  : CachedNetworkImage(
                      imageUrl: event.heroImagePath!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => EventHeroFallback(category: event.category),
                      errorWidget: (context, url, error) => EventHeroFallback(category: event.category),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(FlcSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (event.category != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: FlcSpace.xxs),
                      child: Text(event.category!.toUpperCase(), style: FlcTextStyles.overline.copyWith(color: FlcColors.accent(context))),
                    ),
                  Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlcTextStyles.h3),
                  const SizedBox(height: FlcSpace.xxs),
                  Text(
                    '$when · ${event.venueRoom ?? event.venueName}${event.isOnline ? ' · Also online' : ''}',
                    style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
                  ),
                  if (event.summary != null && event.summary!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: FlcSpace.xs),
                    Text(event.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlcTextStyles.bodySmall),
                  ],
                  if (event.isPromoted || sellingFast || soldOut || event.membersOnly) ...<Widget>[
                    const SizedBox(height: FlcSpace.sm),
                    Wrap(
                      spacing: FlcSpace.xs,
                      runSpacing: FlcSpace.xs,
                      children: <Widget>[
                        EventBadges(highlight: event.highlight, perks: event.perks, sellingFast: sellingFast, soldOut: soldOut, dense: true),
                        if (event.membersOnly) const _MembersChip(),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembersChip extends StatelessWidget {
  const _MembersChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FlcSpace.xs, vertical: 3),
      decoration: BoxDecoration(
        color: FlcColors.brand.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(FlcRadius.input),
      ),
      child: Text('Members only', style: FlcTextStyles.caption.copyWith(color: FlcColors.accent(context), fontWeight: FontWeight.w600)),
    );
  }
}
